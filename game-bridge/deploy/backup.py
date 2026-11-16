"""Root-only online snapshot and isolated restore drill. Never overwrites live state."""
import argparse,hashlib,json,os,re,secrets,shutil,sqlite3,time
from pathlib import Path
BASE=Path('/var/backups/mavka-game-bridge')
STATE=Path('/var/lib/mavka-game-bridge')
def verify(folder):
 with sqlite3.connect('file:'+str(folder/'queue.sqlite')+'?mode=ro&immutable=1',uri=True) as c:
  if c.execute('PRAGMA integrity_check').fetchone()[0]!='ok':raise ValueError('SQLite integrity')
  rows=c.execute('SELECT job,name,sha256,size FROM artifacts').fetchall()
 for job,name,sha,size in rows:
  p=folder/'artifacts'/job/name
  if not p.resolve().is_relative_to(folder.resolve()) or p.is_symlink():raise ValueError('backup escape')
  raw=p.read_bytes()
  if len(raw)!=size or hashlib.sha256(raw).hexdigest()!=sha:raise ValueError('artifact integrity')
 return len(rows)
def create():
 folder=BASE/('snapshot-'+time.strftime('%Y%m%dT%H%M%SZ',time.gmtime())+'-'+secrets.token_hex(3));folder.mkdir(mode=0o700)
 src=sqlite3.connect(STATE/'queue.sqlite');dst=sqlite3.connect(folder/'queue.sqlite')
 try:src.backup(dst)
 finally:dst.close();src.close()
 with sqlite3.connect(folder/'queue.sqlite') as c:rows=c.execute('SELECT job,name FROM artifacts').fetchall()
 for job,name in rows:
  if not re.fullmatch('[a-zA-Z0-9_-]{1,80}',job) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}\.[a-z0-9]+',name):raise ValueError('artifact path')
  src=STATE/'artifacts'/job/name
  if not src.resolve().is_relative_to((STATE/'artifacts').resolve()) or src.is_symlink():raise ValueError('source escape')
  dst=folder/'artifacts'/job/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 shutil.copyfile('/etc/mavka-game-bridge/credentials.json',folder/'credentials.json');(folder/'credentials.json').chmod(0o600)
 (folder/'release.txt').write_text(os.readlink('/opt/mavka-game-bridge/current')+'\n')
 verify(folder);return folder
if __name__=='__main__':
 if os.geteuid()!=0:raise SystemExit('root required for private backup')
 os.umask(0o077);BASE.mkdir(mode=0o700,exist_ok=True)
 p=argparse.ArgumentParser();p.add_argument('operation',choices=['create','verify','restore-test']);p.add_argument('path',nargs='?');a=p.parse_args()
 if a.operation=='create':print(create())
 else:
  folder=Path(a.path).resolve()
  if folder.parent!=BASE or not folder.name.startswith('snapshot-'):raise SystemExit('snapshot path denied')
  print('verified_artifacts',verify(folder))
  if a.operation=='restore-test':
   dest=BASE/('restore-drill-'+secrets.token_hex(6));dest.mkdir(mode=0o700)
   shutil.copyfile(folder/'queue.sqlite',dest/'queue.sqlite')
   if (folder/'artifacts').exists():shutil.copytree(folder/'artifacts',dest/'artifacts')
   print('restored_artifacts',verify(dest));print('isolated_restore',dest)
