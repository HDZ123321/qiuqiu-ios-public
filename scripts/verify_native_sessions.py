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
        app.router.add_post('/v1/runs',native._handle_runs)
        app.router.add_get('/v1/runs/{run_id}',native._handle_get_run)
        async with TestServer(app) as server, ClientSession() as upstream:
            restricted = web.Application()
            restricted['app_key']='app-fixture'; restricted['native_key']='native-fixture'
            restricted['registry']=proxy.Registry(Path(home)/'app.sqlite')
            restricted['registry'].remember('run_fixture','owned')
            restricted['sessions_enabled']=True
            restricted['profile_sessions_db']=Path(home)/'state.db'
            restricted['active']=0
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
                # Explicit adoption, no fork, no source/title rewrite, and no model call.
                from unittest.mock import patch
                from types import SimpleNamespace
                from gateway.platforms import api_server_runs
                db.set_session_title('foreign','Synthetic WeChat title')
                assert not restricted['registry'].session('foreign')
                assert (await client.post('/v1/profile/sessions/foreign/adopt')).status==401
                adopted=await client.post('/v1/profile/sessions/foreign/adopt',headers=headers)
                assert adopted.status==200, await adopted.text()
                assert restricted['registry'].adopted('foreign')
                assert not restricted['registry'].owns('run_foreign')
                # Real durable lease held by another channel blocks POST before admission.
                assert db.try_acquire_session_turn_lease('foreign','synthetic-channel')
                intent={**headers,'Idempotency-Key':'same-original-intent'}
                body={'session_id':'foreign','input':'synthetic continued turn','conversation_history':[{'role':'user','content':'must not replace canonical context'}]}
                busy=await client.post('/v1/runs',headers=intent,json=body)
                assert busy.status==409
                db.release_session_turn_lease('foreign','synthetic-channel')
                observed=[]
                def fake_worker(adapter, launch, agent, approval_notify, **kwargs):
                    observed.append((launch.session_id,launch.conversation_history))
                    assert launch.session_id=='foreign'
                    assert any(m.get('content')=='synthetic foreign channel' for m in launch.conversation_history)
                    assert not any(m.get('content')=='must not replace canonical context' for m in launch.conversation_history)
                    assert db.try_acquire_session_turn_lease(launch.session_id,'synthetic-agent')
                    db.append_message(launch.session_id,'user',launch.user_message,turn_lease_holder='synthetic-agent')
                    db.append_message(launch.session_id,'assistant','synthetic finalized answer',turn_lease_holder='synthetic-agent')
                    db.release_session_turn_lease(launch.session_id,'synthetic-agent')
                    return {'final_response':'synthetic finalized answer'}, {}, {}
                with patch.object(native,'_create_agent',return_value=SimpleNamespace()), patch.object(api_server_runs,'_run_agent_sync',side_effect=fake_worker):
                    accepted=await client.post('/v1/runs',headers=intent,json=body)
                    assert accepted.status==202, await accepted.text()
                    rid=(await accepted.json())['run_id']
                    for _ in range(100):
                        status=await (await client.get('/v1/runs/'+rid,headers=headers)).json()
                        if status['status'] in ('completed','failed'): break
                        await asyncio.sleep(.02)
                    assert status['status']=='completed',status
                    replay=await client.post('/v1/runs',headers=intent,json=body)
                    assert replay.status==202
                    assert (await replay.json())['run_id']==rid
                assert len(observed)==1
                original=db.get_session('foreign')
                assert original['source']=='wechat' and original['title']=='Synthetic WeChat title'
                rows=await (await client.get('/v1/profile/sessions/foreign/messages',headers=headers)).json()
                assert [m['content'] for m in rows['items']]==['synthetic foreign channel','synthetic continued turn','synthetic finalized answer']
                db.create_session('internal','subagent')
                assert (await client.post('/v1/profile/sessions/internal/adopt',headers=headers)).status==403
                print('PASS: real native Runs handler + mock agent, original WeChat ID/source/title/history, lease busy rejection, exact idempotent replay, finalized history sync; no model invoked')
                print('PASS: real native SessionDB -> authenticated native messages handler -> owned restricted route; text only, foreign rejected')
            restricted['registry'].db.close()
        db.close()

if __name__=='__main__': asyncio.run(main())
