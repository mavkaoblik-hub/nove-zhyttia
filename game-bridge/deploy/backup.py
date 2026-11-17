"""Root-only online snapshot and isolated restore drill. Never overwrites live state."""
import argparse,hashlib,json,os,re,secrets,shutil,sqlite3,time,subprocess
from pathlib import Path
BASE=Path('/var/backups/mavka-game-bridge')
STATE=Path('/var/lib/mavka-game-bridge')
def verify(folder):
 with sqlite3.connect('file:'+str(folder/'queue.sqlite')+'?mode=ro&immutable=1',uri=True) as c:
  if c.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('SQLite integrity')
  rows=c.execute('SELECT job,name,sha256,size FROM artifacts').fetchall()
  has_transfers=c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='transfers'").fetchone()
  transfers=c.execute('SELECT sha,size,complete FROM transfers').fetchall() if has_transfers else []
  chunks=c.execute('SELECT sha,idx,size,digest FROM transfer_chunks').fetchall() if has_transfers else []
 for job,name,sha,size in rows:
  p=folder/'artifacts'/job/name
  if not p.resolve().is_relative_to(folder.resolve()) or p.is_symlink():raise ValueError('backup escape')
  raw=p.read_bytes()
  if len(raw)!=size or hashlib.sha256(raw).hexdigest()!=sha:raise ValueError('artifact integrity')
 for digest,index,size,expected in chunks:
  p=folder/'transfers'/digest/(str(index)+'.chunk')
  if p.is_symlink() or not p.resolve().is_relative_to(folder.resolve()):raise ValueError('chunk path')
  raw=p.read_bytes()
  if len(raw)!=size or hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('chunk integrity')
 for digest,size,complete in transfers:
  if complete:
   p=folder/'transfers'/digest/'package.zip'
   if p.is_symlink() or not p.resolve().is_relative_to(folder.resolve()):raise ValueError('package path')
   h=hashlib.sha256();total=0
   with open(p,'rb') as f:
    while raw:=f.read(1024*1024):h.update(raw);total+=len(raw)
   if total!=size or h.hexdigest()!=digest:raise ValueError('package integrity')
 return len(rows)
def create():
 folder=BASE/('snapshot-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-'+secrets.token_hex(3));folder.mkdir(mode=0o700)
 # Open live WAL with the service UID, so backup never creates root-owned WAL/SHM.
 staging=STATE/('.backup-'+secrets.token_hex(12)+'.sqlite')
 code='import sqlite3,sys;s=sqlite3.connect(sys.argv[1]);d=sqlite3.connect(sys.argv[2]);s.backup(d);d.close();s.close()'
 try:
  subprocess.run(['/usr/sbin/runuser','-u','mavka-game-bridge','--','/usr/bin/python3','-I','-c',code,str(STATE/'queue.sqlite'),str(staging)],check=True)
  if staging.is_symlink() or staging.resolve().parent!=STATE:raise ValueError('backup staging escape')
  shutil.copyfile(staging,folder/'queue.sqlite')
 finally:
  if staging.exists():staging.unlink()
 with sqlite3.connect(folder/'queue.sqlite') as c:
  rows=c.execute('SELECT job,name FROM artifacts').fetchall()
  has_transfers=c.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='transfers'").fetchone()
  chunks=c.execute('SELECT sha,idx FROM transfer_chunks').fetchall() if has_transfers else []
  packages=c.execute('SELECT sha FROM transfers WHERE complete=1').fetchall() if has_transfers else []
 for job,name in rows:
  if not re.fullmatch('[a-zA-Z0-9_-]{1,80}',job) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}\.[a-z0-9]+',name):raise ValueError('artifact path')
  src=STATE/'artifacts'/job/name
  if not src.resolve().is_relative_to((STATE/'artifacts').resolve()) or src.is_symlink():raise ValueError('source escape')
  dst=folder/'artifacts'/job/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for digest,index in chunks:
  if not re.fullmatch('[a-f0-9]{64}',digest) or type(index) is not int or index<0:raise ValueError('chunk identity')
  src=STATE/'transfers'/digest/(str(index)+'.chunk')
  if src.is_symlink() or not src.resolve().is_relative_to((STATE/'transfers').resolve()):raise ValueError('chunk escape')
  dst=folder/'transfers'/digest/(str(index)+'.chunk');dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for (digest,) in packages:
  src=STATE/'transfers'/digest/'package.zip'
  if src.is_symlink() or not src.resolve().is_relative_to((STATE/'transfers').resolve()):raise ValueError('package escape')
  dst=folder/'transfers'/digest/'package.zip';dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 shutil.copyfile('/etc/mavka-game-bridge/credentials.json',folder/'credentials.json');(folder/'credentials.json').chmod(0o600)
 (folder/'release.txt').write_text(os.readlink('/opt/mavka-game-bridge/current')+'\n')
 verify(folder);return folder
def prune(keep=7):
 # Delete only verified snapshot directories created by this tool. Preserve restore drills.
 snapshots=sorted([p for p in BASE.glob('snapshot-*') if p.is_dir() and not p.is_symlink()],reverse=True)
 for old in snapshots[keep:]:
  if old.resolve().parent!=BASE or not re.fullmatch(r'snapshot-\d{8}T\d{6}Z-[a-f0-9]{6}',old.name):raise ValueError('retention path')
  verify(old);shutil.rmtree(old)
if __name__=='__main__':
 if os.geteuid()!=0:raise SystemExit('root required for private backup')
 os.umask(0o077);BASE.mkdir(mode=0o700,exist_ok=True)
 p=argparse.ArgumentParser();p.add_argument('operation',choices=['create','verify','restore-test']);p.add_argument('path',nargs='?');p.add_argument('--prune',action='store_true');a=p.parse_args()
 if a.operation=='create':
  print(create())
  if a.prune:prune()
 else:
  folder=Path(a.path).resolve()
  if folder.parent!=BASE or not folder.name.startswith('snapshot-'):raise SystemExit('snapshot path denied')
  print('verified_artifacts',verify(folder))
  if a.operation=='restore-test':
   dest=BASE/('restore-drill-'+secrets.token_hex(6));dest.mkdir(mode=0o700)
   shutil.copyfile(folder/'queue.sqlite',dest/'queue.sqlite')
   if (folder/'artifacts').exists():shutil.copytree(folder/'artifacts',dest/'artifacts')
   if (folder/'transfers').exists():shutil.copytree(folder/'transfers',dest/'transfers')
   print('restored_artifacts',verify(dest));print('isolated_restore',dest)
