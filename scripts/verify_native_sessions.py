"""Run in a fresh process with a fresh HERMES_HOME; never open user transcripts."""
import os
import sys
import tempfile
from pathlib import Path
import asyncio

async def main():
    root = Path(os.environ['QIU_HERMES_SOURCE'])
    with tempfile.TemporaryDirectory() as home:
        os.environ['HERMES_HOME'] = home
        sys.path.insert(0, str(root))
        from hermes_state import SessionDB
        from gateway.config import PlatformConfig
        from gateway.platforms.api_server import APIServerAdapter
        from aiohttp import web, ClientSession
        from aiohttp.test_utils import TestServer, TestClient
        import restricted_proxy as proxy
        db = SessionDB(Path(home)/'state.db')
        db.create_session('owned','api_server')
        db.create_session('foreign','wechat')
        db.append_message('owned','user','synthetic stored question')
        db.append_message('owned','assistant','synthetic stored answer',reasoning='private synthetic reasoning')
        db.append_message('foreign','user','synthetic foreign channel')
        native = APIServerAdapter(PlatformConfig(extra={'key':'native-fixture','model_name':'fixture'}))
        native._session_db = db
        app = web.Application()
        app.router.add_get('/api/sessions/{session_id}/messages',native._handle_session_messages)
        app.router.add_get('/api/sessions/{session_id}',native._handle_get_session)
        db.set_session_title('owned','Synthetic original title')
        async with TestServer(app) as server, ClientSession() as upstream:
            restricted = web.Application()
            restricted['app_key']='app-fixture'; restricted['native_key']='native-fixture'
            restricted['registry']=proxy.Registry(Path(home)/'app.sqlite')
            restricted['registry'].remember('run_fixture','owned')
            restricted['sessions_enabled']=True
            restricted['session_native_base']=str(server.make_url('')).rstrip('/')
            restricted['client']=upstream
            restricted.router.add_route('*','/{tail:.*}',proxy.handle)
            async with TestClient(TestServer(restricted)) as client:
                headers={'Authorization':'Bearer app-fixture'}
                titles=await (await client.get('/v1/app/sessions',headers=headers)).json()
                assert len(titles['items'])==1
                assert titles['items'][0]['title']=='Synthetic original title'
                assert titles['items'][0]['title_source']=='native'
                db.set_session_title('owned','')
                fallback=await (await client.get('/v1/app/sessions',headers=headers)).json()
                assert fallback['items'][0]['title']=='synthetic stored question'
                assert fallback['items'][0]['title_source']=='first_user'
                response=await client.get('/v1/app/sessions/owned/messages',headers=headers)
                assert response.status==200, response.status
                payload=await response.json()
                assert payload['history']=='stored_text', payload
                assert [m['content'] for m in payload['items']]==['synthetic stored question','synthetic stored answer']
                assert all(set(m)=={'id','role','content'} for m in payload['items'])
                assert (await client.get('/v1/app/sessions/foreign/messages',headers=headers)).status==404
                assert (await client.get('/api/sessions',headers=headers)).status==404
                print('PASS: real native SessionDB -> authenticated native messages handler -> owned restricted route; text only, foreign rejected')
            restricted['registry'].db.close()
        db.close()

if __name__=='__main__': asyncio.run(main())
