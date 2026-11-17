import base64,hashlib,json,secrets,sys,tempfile,time,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'gateway'))
from bridge import Bridge,signature,encoded

class Tests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.creds=self.root/'creds.json';self.key='test-only'
  self.creds.write_text(json.dumps({'owner':{'role':'owner','key':self.key,'expires_at':int(time.time())+1000},'pc':{'role':'device','device_id':'pc','key':self.key,'expires_at':int(time.time())+1000}}))
  self.b=Bridge(self.root/'state',self.creds);self.owner={'role':'owner'};self.device={'role':'device','device_id':'pc'}
 def tearDown(self):self.tmp.cleanup()
 def job(self,**kw):
  d=dict(job_id='test',device_id='pc',action='system.health',arguments={},created_at=int(time.time()),expires_at=int(time.time())+600,requested_by='owner',revision_sha='a'*40,idempotency_key='test',approval_required=False);d.update(kw);return d
 def submit(self,**kw):return self.b.dispatch('owner',self.owner,'POST','/v1/jobs',self.job(**kw))
 def lease(self):return self.b.dispatch('pc',self.device,'POST','/v1/lease',{})
 def test_lifecycle_and_duplicate(self):
  self.submit();self.assertEqual(self.submit()['state'],'queued');l=self.lease();self.assertIsNone(self.lease()['job'])
  self.b.dispatch('pc',self.device,'POST','/v1/jobs/test/progress',{'lease':l['lease']})
  self.b.dispatch('pc',self.device,'POST','/v1/jobs/test/result',{'lease':l['lease'],'state':'succeeded','result':{'exit_code':0}})
  self.assertEqual(self.b.dispatch('owner',self.owner,'GET','/v1/jobs/test',{})['state'],'succeeded')
 def test_auth_replay_tampering_expiry(self):
  stamp=str(int(time.time()));nonce=secrets.token_hex(16);body=b'{}';h={'X-Principal':'pc','X-Time':stamp,'X-Nonce':nonce,'X-Signature':signature(self.key,'POST','/v1/lease',stamp,nonce,body)}
  self.b.auth(h,'POST','/v1/lease',body)
  for payload in [body,b'{"tampered":1}']:
   with self.assertRaises(PermissionError):self.b.auth(h,'POST','/v1/lease',payload)
  h['X-Time']='1'
  with self.assertRaises(PermissionError):self.b.auth(h,'POST','/v1/lease',body)
  h['X-Principal']='unknown'
  with self.assertRaises(PermissionError):self.b.auth(h,'POST','/v1/lease',body)
 def test_revocation_and_expired_token(self):
  d=json.loads(self.creds.read_text());d['pc']['expires_at']=0;self.creds.write_text(json.dumps(d))
  with self.assertRaises(PermissionError):self.b.auth({'X-Principal':'pc'},'GET','/v1/status',b'')
  d['pc']['expires_at']=int(time.time())+100;d['pc']['revoked']=True;self.creds.write_text(json.dumps(d))
  with self.assertRaises(PermissionError):self.b.auth({'X-Principal':'pc'},'GET','/v1/status',b'')
 def test_validation(self):
  for kw in [{'action':'shell'},{'job_id':'../escape'},{'device_id':'unknown'},{'revision_sha':'main'},{'expires_at':1},{'requested_by':'intruder'}]:
   with self.assertRaises(ValueError):self.submit(**kw)
 def test_device_isolation(self):
  self.submit()
  with self.assertRaises(PermissionError):self.b.dispatch('other',{'role':'device','device_id':'other'},'GET','/v1/jobs/test',{})
 def test_lost_lease_no_repeat(self):
  self.submit();self.lease()
  with self.b.db() as c:c.execute('UPDATE jobs SET deadline=0')
  self.assertIsNone(self.lease()['job']);self.assertEqual(self.b.dispatch('owner',self.owner,'GET','/v1/jobs/test',{})['state'],'failed')
 def test_cancel(self):
  self.submit();l=self.lease();self.b.dispatch('owner',self.owner,'POST','/v1/jobs/test/cancel',{})
  self.assertEqual(self.b.dispatch('pc',self.device,'POST','/v1/jobs/test/progress',{'lease':l['lease']})['state'],'cancelled')
 def test_artifact_integrity_and_traversal(self):
  self.submit();l=self.lease();d={'lease':l['lease'],'name':'a.png','content':base64.b64encode(b'fixture').decode(),'sha256':hashlib.sha256(b'fixture').hexdigest()}
  for change in [{'name':'../a.png'},{'sha256':'0'*64},{'content':base64.b64encode(b'x'*(8*1024*1024+1)).decode()}]:
   with self.assertRaises(ValueError):self.b.dispatch('pc',self.device,'POST','/v1/jobs/test/artifacts',dict(d,**change))
  self.b.dispatch('pc',self.device,'POST','/v1/jobs/test/artifacts',d)
 def test_restore(self):
  import sqlite3
  self.submit();backup=self.root/'backup.sqlite';restore=self.root/'restore.sqlite'
  with self.b.db() as src,sqlite3.connect(backup) as dst:src.backup(dst)
  with sqlite3.connect(backup) as src,sqlite3.connect(restore) as dst:src.backup(dst)
  with sqlite3.connect(restore) as c:self.assertEqual(c.execute('PRAGMA integrity_check').fetchone()[0],'ok');self.assertEqual(c.execute('SELECT count(*) FROM jobs').fetchone()[0],1)
 def test_idempotency_conflict(self):
  self.submit()
  with self.assertRaises(ValueError):self.submit(action='godot.version')
 def test_connections_closed(self):
  import gc
  gc.collect();before=len(list(Path('/proc/self/fd').iterdir()))
  for i in range(300):self.b.dispatch('owner',self.owner,'GET','/v1/status',{})
  after=len(list(Path('/proc/self/fd').iterdir()))
  self.assertLessEqual(after,before+2,'SQLite handles must close before GC')

if __name__=='__main__':unittest.main()
