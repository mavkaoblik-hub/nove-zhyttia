"""MaVka Game Bridge 1.0. Standard library, private WireGuard transport only."""
import argparse, base64, contextlib, hashlib, hmac, json, os, re, secrets, sqlite3, time, threading
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSION = '1.0.0'
ACTIONS = {'system.health','blender.version','godot.version','workspace.status',
 'workspace.stage_revision','blender.scene.inspect','blender.render','blender.export_gltf',
 'blender.run_approved_script','godot.project.inspect','godot.project.import',
 'godot.project.validate','godot.tests.headless','godot.export','artifact.upload','job.cancel'}
TERMINAL = {'succeeded','failed','cancelled','expired'}
def encoded(x): return json.dumps(x, separators=(',',':'), ensure_ascii=False).encode()
def digest(b): return hashlib.sha256(b).hexdigest()
def signature(key, method, path, stamp, nonce, body):
 return hmac.new(key.encode(), '\n'.join([method,path,str(stamp),nonce,digest(body)]).encode(),hashlib.sha256).hexdigest()

class Bridge:
 def __init__(self, root, credentials):
  self.root=Path(root); self.root.mkdir(parents=True,exist_ok=True)
  self.credentials=Path(credentials)
  with self.db() as c:
   c.executescript('''PRAGMA journal_mode=WAL;
   CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,device TEXT,idem TEXT,body TEXT,state TEXT,lease TEXT,deadline INTEGER,attempts INTEGER DEFAULT 0,result TEXT, UNIQUE(device,idem));
   CREATE TABLE IF NOT EXISTS nonces(principal TEXT,nonce TEXT,created INTEGER,PRIMARY KEY(principal,nonce));
   CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY,heartbeat INTEGER,version TEXT);
   CREATE TABLE IF NOT EXISTS audit(seq INTEGER PRIMARY KEY,at INTEGER,actor TEXT,event TEXT,job TEXT);
   CREATE TABLE IF NOT EXISTS artifacts(job TEXT,name TEXT,sha256 TEXT,size INTEGER,PRIMARY KEY(job,name));
   PRAGMA user_version=1;''')
 @contextlib.contextmanager
 def db(self):
  c=sqlite3.connect(self.root/'queue.sqlite',timeout=10);c.row_factory=sqlite3.Row
  try:
   with c:yield c
  finally:c.close()
 def auth(self,headers,method,path,body):
  creds=json.loads(self.credentials.read_text());who=headers.get('X-Principal','');entry=creds.get(who)
  if not entry or entry.get('revoked') or entry['expires_at']<time.time(): raise PermissionError('unauthorized')
  stamp=headers.get('X-Time','');nonce=headers.get('X-Nonce','')
  if not stamp.isdigit() or abs(int(stamp)-time.time())>60 or not re.fullmatch('[a-f0-9]{32}',nonce):raise PermissionError('stale request')
  expected=signature(entry['key'],method,path,stamp,nonce,body)
  if not hmac.compare_digest(expected,headers.get('X-Signature','')): raise PermissionError('invalid signature')
  try:
   with self.db() as c:
    c.execute('DELETE FROM nonces WHERE created<?',(int(time.time())-120,))
    c.execute('INSERT INTO nonces VALUES(?,?,?)',(who,nonce,int(time.time())))
  except sqlite3.IntegrityError:raise PermissionError('replay')
  return who,entry
 def sweep(self,c):
  now=int(time.time())
  # Never automatically re-lease an uncertain execution. Owner must inspect/reconcile.
  c.execute("UPDATE jobs SET state='failed',result=? WHERE state IN ('leased','running') AND deadline<?",(json.dumps({'error':'lease lost; manual reconciliation required'}),now))
  for r in c.execute("SELECT id,body FROM jobs WHERE state='queued'").fetchall():
   if json.loads(r['body'])['expires_at']<now:c.execute("UPDATE jobs SET state='expired' WHERE id=?",(r['id'],))
 def dispatch(self,who,role,method,path,data):
  now=int(time.time());device=role.get('device_id');owner=role['role']=='owner'
  with self.db() as c:
   c.execute('BEGIN IMMEDIATE');self.sweep(c)
   if owner and path=='/v1/status' and method=='GET':
    return {'version':VERSION,'devices':[dict(x) for x in c.execute('SELECT * FROM devices')],'jobs':[dict(x) for x in c.execute('SELECT id,device,state,attempts FROM jobs ORDER BY rowid DESC LIMIT 100')]}
   if owner and path=='/v1/jobs' and method=='POST':
    required={'job_id','device_id','action','arguments','created_at','expires_at','requested_by','revision_sha','idempotency_key','approval_required'}
    if set(data)!=required:raise ValueError('job fields')
    for k in ['job_id','device_id','idempotency_key']:
     if not isinstance(data[k],str) or not re.fullmatch('[a-zA-Z0-9_-]{1,80}',data[k]):raise ValueError('identifier')
    if data['requested_by']!=who or data['action'] not in ACTIONS or not isinstance(data['arguments'],dict):raise ValueError('action/author')
    if not re.fullmatch('[a-f0-9]{40}',data['revision_sha']):raise ValueError('revision SHA')
    if type(data['approval_required']) is not bool:raise ValueError('approval')
    if type(data['created_at']) is not int or type(data['expires_at']) is not int or not now-60<=data['created_at']<=now+60 or not now<data['expires_at']<=now+86400:raise ValueError('expiry')
    registered=json.loads(self.credentials.read_text()).values()
    if not any(x.get('device_id')==data['device_id'] and not x.get('revoked') and x['expires_at']>now for x in registered):raise ValueError('unregistered device')
    old=c.execute('SELECT * FROM jobs WHERE device=? AND idem=?',(data['device_id'],data['idempotency_key'])).fetchone()
    body=json.dumps(data,sort_keys=True)
    if old:
     if old['body']!=body:raise ValueError('idempotency conflict')
     return {'job_id':old['id'],'state':old['state']}
    if c.execute("SELECT count(*) FROM jobs WHERE state IN ('queued','leased','running')").fetchone()[0]>=100:raise ValueError('queue quota')
    c.execute('INSERT INTO jobs(id,device,idem,body,state) VALUES(?,?,?,?,?)',(data['job_id'],data['device_id'],data['idempotency_key'],body,'queued'))
    c.execute('INSERT INTO audit(at,actor,event,job) VALUES(?,?,?,?)',(now,who,'submit',data['job_id']))
    return {'job_id':data['job_id'],'state':'queued'}
   if not owner and path=='/v1/heartbeat' and method=='POST':
    c.execute('INSERT OR REPLACE INTO devices VALUES(?,?,?)',(device,now,str(data.get('version',''))[:40]));return {'ok':True}
   if not owner and path=='/v1/lease' and method=='POST':
    if c.execute("SELECT 1 FROM jobs WHERE device=? AND state IN ('leased','running')",(device,)).fetchone():return {'job':None}
    r=c.execute("SELECT * FROM jobs WHERE device=? AND state='queued' ORDER BY rowid LIMIT 1",(device,)).fetchone()
    if not r:return {'job':None}
    token=secrets.token_hex(32)
    c.execute("UPDATE jobs SET state='leased',lease=?,deadline=?,attempts=attempts+1 WHERE id=?",(token,now+90,r['id']))
    return {'job':json.loads(r['body']),'lease':token}
   m=re.fullmatch(r'/v1/jobs/([a-zA-Z0-9_-]{1,80})(?:/(progress|result|cancel|artifacts))?',path)
   if not m:raise ValueError('unknown route')
   jid,op=m.groups();r=c.execute('SELECT * FROM jobs WHERE id=?',(jid,)).fetchone()
   if not r:raise ValueError('unknown job')
   if not owner and r['device']!=device:raise PermissionError('device mismatch')
   if method=='GET' and not op:
    return {'job':json.loads(r['body']),'state':r['state'],'result':json.loads(r['result']) if r['result'] else None,'artifacts':[dict(x) for x in c.execute('SELECT name,sha256,size FROM artifacts WHERE job=?',(jid,))]}
   if owner and op=='cancel' and method=='POST':
    if r['state'] not in TERMINAL:c.execute("UPDATE jobs SET state='cancelled' WHERE id=?",(jid,))
    c.execute('INSERT INTO audit(at,actor,event,job) VALUES(?,?,?,?)',(now,who,'cancel',jid));return {'state':'cancelled' if r['state'] not in TERMINAL else r['state']}
   if owner or method!='POST' or not hmac.compare_digest(str(data.get('lease','')),r['lease'] or '!'):raise PermissionError('lease')
   if r['state'] in TERMINAL:return {'state':r['state']}
   if op=='progress':
    c.execute("UPDATE jobs SET state='running',deadline=? WHERE id=?",(now+90,jid))
    c.execute('UPDATE devices SET heartbeat=? WHERE id=?',(now,device));return {'state':'running'}
   if op=='result':
    if data.get('state') not in {'succeeded','failed','cancelled'}:raise ValueError('result state')
    if len(encoded(data))>65536:raise ValueError('result quota')
    c.execute('UPDATE jobs SET state=?,result=? WHERE id=?',(data['state'],json.dumps(data.get('result',{})),jid))
    c.execute('INSERT INTO audit(at,actor,event,job) VALUES(?,?,?,?)',(now,who,data['state'],jid));return {'state':data['state']}
   if op=='artifacts':
    name=data.get('name','')
    if not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}\.(png|glb|gltf|log|json|txt|zip)',name):raise ValueError('artifact name')
    raw=base64.b64decode(data.get('content',''),validate=True)
    if len(raw)>8*1024*1024 or digest(raw)!=data.get('sha256'):raise ValueError('artifact size/hash')
    if c.execute('SELECT COALESCE(sum(size),0) FROM artifacts').fetchone()[0]+len(raw)>256*1024*1024:raise ValueError('storage quota')
    if c.execute('SELECT 1 FROM artifacts WHERE job=? AND name=?',(jid,name)).fetchone():raise ValueError('immutable artifact')
    folder=self.root/'artifacts'/jid;folder.mkdir(parents=True,exist_ok=True)
    with open(folder/name,'xb') as f:f.write(raw)
    c.execute('INSERT INTO artifacts VALUES(?,?,?,?)',(jid,name,digest(raw),len(raw)));return {'sha256':digest(raw)}
   raise ValueError('unsupported operation')

class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):self.handle_api()
 def do_POST(self):self.handle_api()
 def handle_api(self):
  self.connection.settimeout(15)
  try:
   if self.client_address[0] not in self.server.allowed:raise PermissionError('network')
   n=int(self.headers.get('Content-Length','0'))
   if n<0 or n>12*1024*1024:raise ValueError('body quota')
   if self.headers.get('Transfer-Encoding'):raise ValueError('encoding')
   body=self.rfile.read(n)
   if len(body)!=n:raise ValueError('body')
   who,role=self.server.bridge.auth(self.headers,self.command,self.path,body)
   data=json.loads(body) if body else {}
   result=self.server.bridge.dispatch(who,role,self.command,self.path,data);code=200
  except PermissionError:code=403;result={'error':'forbidden'}
  except (ValueError,KeyError,TypeError,sqlite3.IntegrityError):code=400;result={'error':'invalid request'}
  except Exception as error:
   import traceback
   frame=traceback.extract_tb(error.__traceback__)[-1]
   print('bridge_error',type(error).__name__,frame.name,frame.lineno,flush=True)
   code=500;result={'error':'internal error'}
  out=encoded(result);self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(out)));self.end_headers();self.wfile.write(out)

class BoundedServer(ThreadingHTTPServer):
 # Bound concurrency and connection rate before allocating request threads/body buffers.
 def __init__(self,*args,**kwargs):
  self.slots=threading.BoundedSemaphore(8);self.rate_lock=threading.Lock();self.window=0;self.count=0
  super().__init__(*args,**kwargs)
 def verify_request(self,request,client_address):
  with self.rate_lock:
   now=int(time.time())
   if now!=self.window:self.window=now;self.count=0
   self.count+=1
   return client_address[0] in self.allowed and self.count<=20
 def process_request(self,request,client_address):
  if not self.slots.acquire(False):self.shutdown_request(request);return
  try:super().process_request(request,client_address)
  except BaseException:self.slots.release();raise
 def process_request_thread(self,request,client_address):
  try:super().process_request_thread(request,client_address)
  finally:self.slots.release()

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--state',required=True);p.add_argument('--credentials',required=True);p.add_argument('--host',default='127.0.0.1');p.add_argument('--port',type=int,default=18773);p.add_argument('--allow',action='append',default=['127.0.0.1']);a=p.parse_args()
 os.umask(0o077)
 server=BoundedServer((a.host,a.port),Handler);server.bridge=Bridge(a.state,a.credentials);server.allowed=a.allow;server.serve_forever()
