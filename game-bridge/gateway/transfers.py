"""Immutable, chunked development packages. No archive extraction on gateway."""
import base64,hashlib,json,os,re,secrets
from pathlib import Path
CHUNK=1024*1024
MAX_SIZE=256*1024*1024
def sha(raw):return hashlib.sha256(raw).hexdigest()
def initialize(bridge):
 with bridge.db() as c:
  c.executescript('''CREATE TABLE IF NOT EXISTS transfers(sha TEXT PRIMARY KEY,device TEXT,project TEXT,kind TEXT,size INTEGER,complete INTEGER DEFAULT 0,created INTEGER);
  CREATE TABLE IF NOT EXISTS transfer_chunks(sha TEXT,idx INTEGER,size INTEGER,digest TEXT,PRIMARY KEY(sha,idx));
  PRAGMA user_version=2;''')
def valid_hash(value):return isinstance(value,str) and re.fullmatch('[a-f0-9]{64}',value)
def operate(bridge,c,principal,role,data,job=None):
 import time
 owner=role['role']=='owner';op=data.get('op');digest=data.get('sha256','')
 if not valid_hash(digest):raise ValueError('transfer SHA256')
 root=bridge.root/'transfers';root.mkdir(exist_ok=True)
 folder=root/digest
 if folder.is_symlink():raise ValueError('transfer symlink')
 if not owner:
  if job is None or job['state'] not in {'leased','running'}:raise PermissionError('active transfer lease required')
  args=json.loads(job['body'])['arguments'];action=json.loads(job['body'])['action']
  if action not in {'files.push','files.pull','pipeline.run'}:raise PermissionError('transfer action')
  if op=='download':
   if action!='files.pull' or args.get('package_sha256')!=digest:raise PermissionError('package binding')
  elif action not in {'files.push','pipeline.run'}:raise PermissionError('upload action')
 if op=='init':
  device=data.get('device_id');project=data.get('project_id');size=data.get('size');kind='incoming' if owner else 'outgoing'
  if not isinstance(device,str) or not re.fullmatch('[a-zA-Z0-9_-]{1,80}',device) or not isinstance(project,str) or not re.fullmatch('[a-f0-9]{32}',project):raise ValueError('transfer identity')
  if not owner and (device!=role.get('device_id') or project!=args.get('project_id')):raise PermissionError('project binding')
  if type(size) is not int or not 0<size<=MAX_SIZE:raise ValueError('transfer quota')
  old=c.execute('SELECT * FROM transfers WHERE sha=?',(digest,)).fetchone()
  if old:
   if (old['device'],old['project'],old['size'])!=(device,project,size):raise ValueError('immutable transfer metadata')
   return {'sha256':digest,'complete':bool(old['complete'])}
  if c.execute('SELECT COALESCE(sum(size),0) FROM transfers').fetchone()[0]+size>1024*1024*1024:raise ValueError('total transfer quota')
  folder.mkdir(mode=0o700,exist_ok=True)
  c.execute('INSERT INTO transfers(sha,device,project,kind,size,created) VALUES(?,?,?,?,?,?)',(digest,device,project,kind,size,int(time.time())))
  return {'sha256':digest,'complete':False}
 row=c.execute('SELECT * FROM transfers WHERE sha=?',(digest,)).fetchone()
 if not row:raise ValueError('unknown transfer')
 if not owner and (row['device']!=role.get('device_id') or row['project']!=args.get('project_id')):raise PermissionError('transfer device/project')
 if op=='chunk':
  if row['complete']:raise ValueError('immutable completed transfer')
  i=data.get('index')
  if type(i) is not int or not 0<=i<(row['size']+CHUNK-1)//CHUNK:raise ValueError('chunk index')
  raw=base64.b64decode(data.get('content',''),validate=True)
  expected=min(CHUNK,row['size']-i*CHUNK)
  if len(raw)!=expected or sha(raw)!=data.get('chunk_sha256'):raise ValueError('chunk integrity')
  old=c.execute('SELECT digest FROM transfer_chunks WHERE sha=? AND idx=?',(digest,i)).fetchone()
  if old:
   if old[0]!=sha(raw):raise ValueError('immutable chunk')
   return {'index':i,'sha256':sha(raw)}
  path=folder/(str(i)+'.chunk')
  if path.exists():
   if path.is_symlink() or sha(path.read_bytes())!=sha(raw):raise ValueError('orphan chunk conflict')
  else:
   with open(path,'xb') as f:f.write(raw)
  c.execute('INSERT INTO transfer_chunks VALUES(?,?,?,?)',(digest,i,len(raw),sha(raw)))
  return {'index':i,'sha256':sha(raw)}
 if op=='complete':
  if row['complete']:return {'sha256':digest,'size':row['size'],'complete':True}
  n=(row['size']+CHUNK-1)//CHUNK
  if c.execute('SELECT count(*) FROM transfer_chunks WHERE sha=?',(digest,)).fetchone()[0]!=n:raise ValueError('missing chunks')
  h=hashlib.sha256();total=0;tmp=folder/('assembling-'+secrets.token_hex(8))
  try:
   with open(tmp,'xb') as out:
    for i in range(n):
     path=folder/(str(i)+'.chunk')
     if path.is_symlink():raise ValueError('chunk symlink')
     raw=path.read_bytes();h.update(raw);total+=len(raw);out.write(raw)
   if h.hexdigest()!=digest or total!=row['size']:raise ValueError('package integrity')
   os.replace(tmp,folder/'package.zip')
  finally:
   if tmp.exists():tmp.unlink()
  c.execute('UPDATE transfers SET complete=1 WHERE sha=?',(digest,))
  # Chunks remain for resumability/audit; quotas account for up to 2x package storage.
  return {'sha256':digest,'size':total,'complete':True}
 if op=='download':
  if not row['complete']:raise ValueError('incomplete transfer')
  i=data.get('index')
  if type(i) is not int or not 0<=i<(row['size']+CHUNK-1)//CHUNK:raise ValueError('chunk index')
  p=folder/'package.zip'
  if p.is_symlink():raise ValueError('package symlink')
  with open(p,'rb') as f:f.seek(i*CHUNK);raw=f.read(CHUNK)
  return {'sha256':digest,'size':row['size'],'index':i,'chunk_sha256':sha(raw),'content':base64.b64encode(raw).decode()}
 if op=='status':return dict(row)
 raise ValueError('transfer operation')
