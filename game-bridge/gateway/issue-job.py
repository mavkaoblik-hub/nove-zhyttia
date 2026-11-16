"""Typed owner submission helper; runs through the existing Oracle plugin."""
import argparse,json,os,secrets,subprocess,tempfile,time
from pathlib import Path
from bridge import ACTIONS
p=argparse.ArgumentParser();p.add_argument('action',choices=sorted(ACTIONS));p.add_argument('--device',default='dev-pc');p.add_argument('--revision',required=True);p.add_argument('--arguments',default='{}');a=p.parse_args()
now=int(time.time());jid='job-'+str(now)+'-'+secrets.token_hex(4)
d=dict(job_id=jid,device_id=a.device,action=a.action,arguments=json.loads(a.arguments),created_at=now,expires_at=now+1800,requested_by='owner',revision_sha=a.revision,idempotency_key=jid,approval_required=a.action not in {'system.health','blender.version','godot.version','workspace.status','workspace.results'})
fd,path=tempfile.mkstemp(prefix='game-bridge-',suffix='.json')
try:
 with os.fdopen(fd,'w') as f:json.dump(d,f)
 subprocess.run(['/usr/bin/python3',str(Path(__file__).with_name('owner.py')),'submit',path],check=True)
finally:os.unlink(path)
