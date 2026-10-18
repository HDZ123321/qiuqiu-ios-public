"""Fresh-process native approval handler acceptance, isolated HERMES_HOME, zero model calls."""
import os
import sys
import tempfile
import asyncio
from pathlib import Path

async def main():
    with tempfile.TemporaryDirectory() as d:
        os.environ['HERMES_HOME']=d
        sys.path.insert(0,os.environ['QIU_HERMES_SOURCE'])
        from gateway.config import PlatformConfig
        from gateway.platforms.api_server import APIServerAdapter
        from gateway.platforms import api_server_runs
        from aiohttp import web, ClientSession
        from aiohttp.test_utils import TestServer,TestClient
        from unittest.mock import patch
        import restricted_proxy as proxy
        from workspace_bridge import Workspace
        native=APIServerAdapter(PlatformConfig(extra={'key':'native-fixture','model_name':'fixture'}))
        native._run_approval_sessions['run_fixture']='synthetic-session'
        native._set_run_status('run_fixture','waiting_for_approval',approval={'request_id':'request_fixture','choices':['once','deny']})
        app=web.Application(); app.router.add_post('/v1/runs/{run_id}/approval',native._handle_run_approval); app.router.add_get('/v1/runs/{run_id}',native._handle_get_run)
        async with TestServer(app) as server, ClientSession() as session:
            restricted=web.Application(); restricted['app_key']='app-fixture'; restricted['native_key']='native-fixture'; restricted['registry']=proxy.Registry(Path(d)/'registry.sqlite'); restricted['registry'].remember('run_fixture','synthetic-session'); restricted['client']=session; restricted['active']=0; restricted['session_native_base']=str(server.make_url('')).rstrip('/')
            restricted.router.add_route('*','/{tail:.*}',proxy.handle)
            calls=[]
            def resolve(key,choice,resolve_all=False,request_id=None):
                calls.append((key,choice,resolve_all,request_id)); return int(request_id=='request_fixture')
            with patch.object(api_server_runs,'_load_owned_run',return_value=('run_fixture',{},None,None,None)),patch('tools.approval.resolve_gateway_approval',side_effect=resolve):
                async with TestClient(TestServer(restricted)) as c:
                    h={'Authorization':'Bearer app-fixture'}; route='/v1/runs/run_fixture/approval'
                    for invalid in [{'choice':'always','request_id':'request_fixture'},{'choice':'once','request_id':'request_fixture','all':True},{'choice':'once'}]: assert (await c.post(route,headers=h,json=invalid)).status==400
                    assert not calls
                    assert (await c.post(route,headers=h,json={'choice':'once','request_id':'stale'})).status==409
                    for choice in ['once','deny']:
                        result=await c.post(route,headers=h,json={'choice':choice,'request_id':'request_fixture'}); assert result.status==200,await result.text()
                        payload=await result.json(); assert payload['resolved']==1 and payload['choice']==choice
                        assert native._run_statuses['run_fixture']['status']=='running'
                    assert calls[-2:]==[('synthetic-session','once',False,'request_fixture'),('synthetic-session','deny',False,'request_fixture')]
        print('PASS: actual native approval handler -> exact waiter once/deny; stale 409; session/always/all/missing-ID rejected by restricted proxy; zero model calls')

if __name__=='__main__': asyncio.run(main())
