"""Owner CLI through existing vm_exec + sudo; no credentials in shell arguments."""
import argparse,json,secrets,time,urllib.request,sqlite3,os
from pathlib import Path
from bridge import signature,encoded
p=argparse.ArgumentParser();p.add_argument('operation',choices=['status','submit','get','cancel','revoke','backup','verify-backup']);p.add_argument('value',nargs='?');a=p.parse_args()
if a.operation=='revoke':
 import fcntl
 path=Path('/etc/mavka-game-bridge/credentials.json')
 with open(str(path)+'.lock','w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX);d=json.loads(path.read_text());d['device-'+a.value]['revoked']=True
  tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(d));os.chmod(tmp,0o640);os.chown(tmp,0,path.stat().st_gid);os.replace(tmp,path)
 print('revoked');raise SystemExit
if a.operation in {'backup','verify-backup'}:
 root=Path('/var/lib/mavka-game-bridge');folder=Path('/var/backups/mavka-game-bridge');folder.mkdir(mode=0o700,exist_ok=True)
 if a.operation=='backup':
  dest=folder/(time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'.sqlite')
  with sqlite3.connect(root/'queue.sqlite') as src,sqlite3.connect(dest) as dst:src.backup(dst)
  os.chmod(dest,0o600);print(dest)
 else:
  path=Path(a.value).resolve()
  if path.parent!=folder:raise SystemExit('backup path denied')
  with sqlite3.connect(path) as c:print(c.execute('PRAGMA integrity_check').fetchone()[0])
 raise SystemExit
creds=json.loads(Path('/etc/mavka-game-bridge/credentials.json').read_text());key=creds['owner']['key']
path='/v1/status';method='GET';data=None
if a.operation=='submit':path='/v1/jobs';method='POST';data=json.loads(Path(a.value).read_text())
if a.operation in {'get','cancel'}:
 import re
 if not re.fullmatch('[a-zA-Z0-9_-]{1,80}',a.value):raise SystemExit('job ID')
 path='/v1/jobs/'+a.value
 if a.operation=='cancel':path+='/cancel';method='POST';data={}
body=encoded(data) if data is not None else b'';stamp=str(int(time.time()));nonce=secrets.token_hex(16)
r=urllib.request.Request('http://10.77.0.1:18773'+path,data=body if method=='POST' else None,method=method,headers={'X-Principal':'owner','X-Time':stamp,'X-Nonce':nonce,'X-Signature':signature(key,method,path,stamp,nonce,body),'Content-Type':'application/json'})
with urllib.request.urlopen(r,timeout=15) as response:print(json.dumps(json.load(response),ensure_ascii=False,indent=2))
