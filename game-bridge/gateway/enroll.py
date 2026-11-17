"""Run only via owner's existing sudo SSH session. Secrets never go to logs."""
import fcntl,json,os,re,secrets,sys,time
from pathlib import Path
p=Path('/etc/mavka-game-bridge/credentials.json')
device=sys.argv[1]
if not re.fullmatch('[a-zA-Z0-9_-]{1,60}',device):raise SystemExit('invalid device')
with open(str(p)+'.lock','w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 creds=json.loads(p.read_text());principal='device-'+device
 if principal in creds and not creds[principal].get('revoked'):raise SystemExit('device already enrolled; revoke explicitly first')
 entry={'role':'device','device_id':device,'key':secrets.token_hex(32),'expires_at':int(time.time())+30*86400}
 creds[principal]=entry
 tmp=p.with_suffix('.tmp');tmp.write_text(json.dumps(creds));os.chmod(tmp,0o640);os.chown(tmp,0,p.stat().st_gid);os.replace(tmp,p)
 print(json.dumps({'principal':principal,'key':entry['key'],'expires_at':entry['expires_at']}))
