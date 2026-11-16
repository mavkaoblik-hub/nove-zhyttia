"""Owner CLI for verified chunked packages; keys stay on Oracle."""
import argparse,base64,hashlib,json,os,secrets,time,urllib.request,zipfile
from pathlib import Path
from bridge import encoded,signature
from transfers import CHUNK,MAX_SIZE
def request(data):
 key=json.loads(Path('/etc/mavka-game-bridge/credentials.json').read_text())['owner']['key']
 body=encoded(data);stamp=str(int(time.time()));nonce=secrets.token_hex(16);path='/v1/transfers'
 r=urllib.request.Request('http://10.77.0.1:18773'+path,data=body,headers={'X-Principal':'owner','X-Time':stamp,'X-Nonce':nonce,'X-Signature':signature(key,'POST',path,stamp,nonce,body),'Content-Type':'application/json'})
 with urllib.request.urlopen(r,timeout=30) as response:return json.load(response)
def upload(path,device,project):
 raw=path.read_bytes()
 if not 0<len(raw)<=MAX_SIZE:raise ValueError('package quota')
 digest=hashlib.sha256(raw).hexdigest();r=request({'op':'init','sha256':digest,'size':len(raw),'device_id':device,'project_id':project})
 if not r['complete']:
  for i in range((len(raw)+CHUNK-1)//CHUNK):
   chunk=raw[i*CHUNK:(i+1)*CHUNK];request({'op':'chunk','sha256':digest,'index':i,'content':base64.b64encode(chunk).decode(),'chunk_sha256':hashlib.sha256(chunk).hexdigest()});time.sleep(.15)
  request({'op':'complete','sha256':digest})
 return digest
def pack(root,files,project,destination):
 from pathlib import PurePosixPath
 entries=[]
 for name in sorted(files):
  rel=PurePosixPath(name)
  if rel.is_absolute() or any(x in {'','..','.'} for x in rel.parts) or '\\' in name or ':' in name:raise ValueError('relative path')
  p=(root/name).resolve()
  if not p.is_relative_to(root.resolve()) or p.is_symlink():raise ValueError('source escape')
  raw=p.read_bytes();entries.append({'path':name,'size':len(raw),'sha256':hashlib.sha256(raw).hexdigest()})
 if not 1<=len(entries)<=200 or sum(x['size'] for x in entries)>MAX_SIZE:raise ValueError('manifest quota')
 with zipfile.ZipFile(destination,'x',compression=zipfile.ZIP_DEFLATED) as z:
  z.writestr('manifest.json',json.dumps({'version':1,'project_id':project,'files':entries},separators=(',',':')))
  for entry in entries:z.write(root/entry['path'],'files/'+entry['path'])
 return destination
if __name__=='__main__':
 p=argparse.ArgumentParser();sub=p.add_subparsers(dest='op',required=True)
 u=sub.add_parser('upload');u.add_argument('file',type=Path);u.add_argument('--device',required=True);u.add_argument('--project',required=True)
 q=sub.add_parser('pack');q.add_argument('--root',type=Path,required=True);q.add_argument('--files',nargs='+',required=True);q.add_argument('--project',required=True);q.add_argument('--output',type=Path,required=True)
 q=sub.add_parser('status');q.add_argument('sha256')
 a=p.parse_args()
 if a.op=='upload':print(upload(a.file,a.device,a.project))
 elif a.op=='pack':print(pack(a.root,a.files,a.project,a.output))
 else:print(json.dumps(request({'op':'status','sha256':a.sha256}),indent=2))
