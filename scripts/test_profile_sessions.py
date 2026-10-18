"""Synthetic default-profile read scope; no production transcripts or credentials."""
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
import restricted_proxy as proxy

class ProfileSessionsHTTP(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)/'state.sqlite'
        self.db = sqlite3.connect(self.path)
        self.db.executescript('''CREATE TABLE sessions(id TEXT PRIMARY KEY,source TEXT,title TEXT,profile_name TEXT,archived INTEGER,hidden INTEGER,parent_session_id TEXT);
        CREATE TABLE messages(id INTEGER PRIMARY KEY,session_id TEXT,role TEXT,content TEXT,active INTEGER,_compressed_summary INTEGER,display_kind TEXT,tool_calls TEXT,reasoning TEXT);''')
        for i in range(123):
            self.db.execute('INSERT INTO sessions VALUES(?,?,?,?,?,?,?)',(f's_{i}', ['weixin','api_server','cron','subagent'][i%4], None if i%2 else f'Title {i}', 'default',i%2,i%3==0,None))
        self.db.execute('INSERT INTO sessions VALUES(?,?,?,?,?,?,?)',('foreign_profile','weixin','Private other profile','other',0,0,None))
        self.db.commit()
        self.app = web.Application()
        self.app['app_key']='fixture-only'
        self.app['registry']=proxy.Registry(Path(self.tmp.name)/'owned.sqlite')
        self.app['registry'].remember('run_owned','s_1')
        self.app['profile_sessions_db']=self.path
        self.app.router.add_route('*','/{tail:.*}',proxy.handle)
        self.client=TestClient(TestServer(self.app)); await self.client.start_server()
        self.headers={'Authorization':'Bearer fixture-only'}
    async def asyncTearDown(self):
        await self.client.close(); self.app['registry'].db.close(); self.db.close(); self.tmp.cleanup()
    async def get(self,path):
        response=await self.client.get(path,headers=self.headers)
        self.assertEqual(response.status,200)
        return await response.json()
    async def test_all_sources_archived_hidden_paginate_without_granting_write(self):
        before=self.app['registry'].db.execute('SELECT * FROM runs').fetchall()
        self.assertEqual((await self.client.get('/v1/profile/sessions')).status,401)
        page=await self.get('/v1/profile/sessions')
        self.assertEqual(len(page['items']),50)
        self.assertEqual(page['total'],123)
        self.assertTrue(page['has_more'])
        all_items=page['items']; sizes=[len(page['items'])]
        while page['next_cursor'] is not None:
            old=page['next_cursor']
            page=await self.get('/v1/profile/sessions?before='+str(old))
            self.assertEqual(page['has_more'],page['next_cursor'] is not None)
            if page['next_cursor'] is not None: self.assertLess(page['next_cursor'],old)
            all_items+=page['items']; sizes.append(len(page['items']))
        self.assertEqual(sizes,[50,50,23])
        self.assertEqual(len({x['session_id'] for x in all_items}),123)
        self.assertEqual({x['source'] for x in all_items},{'weixin','api_server','cron','subagent'})
        self.assertTrue(any(x['archived'] for x in all_items)); self.assertTrue(any(x['hidden'] for x in all_items))
        self.assertEqual([x['session_id'] for x in all_items if x['can_continue']],['s_1'])
        self.assertEqual(before,self.app['registry'].db.execute('SELECT * FROM runs').fetchall())
        for method,path in [('get','/v1/profile/sessions/foreign_profile/messages'),('post','/v1/profile/sessions'),('delete','/v1/profile/sessions/s_1')]:
            self.assertEqual((await getattr(self.client,method)(path,headers=self.headers)).status,404)
        self.assertEqual((await self.client.get('/v1/profile/sessions?limit=0',headers=self.headers)).status,400)
        self.assertEqual((await self.client.get('/v1/profile/sessions?profile=other',headers=self.headers)).status,404)

    async def test_internal_records_remain_listed_but_prompts_never_export(self):
        self.db.execute("INSERT INTO messages(session_id,role,content,active,_compressed_summary) VALUES('s_3','user','private delegated prompt',1,0)")
        self.db.commit()
        item=await self.get('/v1/profile/sessions/s_3')
        self.assertIsNone(item['title'])
        page=await self.get('/v1/profile/sessions/s_3/messages')
        self.assertEqual(page['history'],'unavailable'); self.assertEqual(page['items'],[])

    async def test_transcript_projection_is_text_only_exact_segment_and_read_only(self):
        rows=[('user','visible question',None),('assistant','visible answer',None),('tool','tool secret',None),('user','hidden secret','hidden'),('assistant','notification secret','internal_notification'),('system','system secret',None),('user','second page',None)]
        for role,content,kind in rows:
            self.db.execute('INSERT INTO messages(session_id,role,content,active,_compressed_summary,display_kind,tool_calls,reasoning) VALUES(?,?,?,?,?,?,?,?)',('s_0',role,content,1,0,kind,'secret tool arguments','secret reasoning'))
        self.db.commit()
        before=self.path.read_bytes()
        page=await self.get('/v1/profile/sessions/s_0/messages?limit=2')
        self.assertEqual(page['total'],3)
        self.assertEqual(page['next_offset'],2)
        self.assertEqual([m['content'] for m in page['items']],['visible question','visible answer'])
        self.assertTrue(all(set(m)=={'id','role','content'} for m in page['items']))
        older=await self.get('/v1/profile/sessions/s_0/messages?limit=2&offset=2')
        self.assertEqual([m['content'] for m in older['items']],['second page'])
        self.assertIsNone(older['next_offset'])
        self.assertEqual(before,self.path.read_bytes())
        self.assertFalse(self.app['registry'].session('s_0'))

    async def test_duplicate_owned_runs_and_migrated_sequences_do_not_duplicate_profile_rows(self):
        self.app['registry'].remember('run_second','s_1')
        page=await self.get('/v1/profile/sessions?limit=100')
        page2=await self.get('/v1/profile/sessions?limit=100&before='+str(page['next_cursor']))
        items=page['items']+page2['items']
        self.assertEqual(len(items),123)
        self.assertEqual(next(x['run_count'] for x in items if x['session_id']=='s_1'),2)
        self.assertEqual(sum(x['can_continue'] for x in items),1)
        self.assertEqual(sum(x['title'] is None for x in items),61)

if __name__=='__main__': unittest.main()
