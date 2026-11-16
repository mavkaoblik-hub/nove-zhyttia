"""Return a bounded chat preview of an existing verified Game Bridge artifact."""
import argparse,base64,hashlib,hmac,io,json,re,secrets,sys,time,urllib.request
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from bridge import signature
def preview(job,name):
 if not re.fullmatch('[a-zA-Z0-9_-]{1,80}',job) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}\.(png|jpg|jpeg)',name):raise ValueError('artifact identifier')
 key=json.loads(Path('/etc/mavka-game-bridge/credentials.json').read_text())['owner']['key']
 path='/v1/jobs/'+job;stamp=str(int(time.time()));nonce=secrets.token_hex(16)
 r=urllib.request.Request('http://10.77.0.1:18773'+path,headers={'X-Principal':'owner','X-Time':stamp,'X-Nonce':nonce,'X-Signature':signature(key,'GET',path,stamp,nonce,b'')})
 with urllib.request.urlopen(r,timeout=10) as response:metadata=json.load(response)
 items=[x for x in metadata['artifacts'] if x['name']==name]
 if metadata['state']!='succeeded' or len(items)!=1 or items[0]['size']>8*1024*1024:raise ValueError('unverified/oversize image')
 root=Path('/var/lib/mavka-game-bridge/artifacts');p=root/job/name
 if p.is_symlink() or not p.resolve().is_relative_to(root.resolve()) or p.stat().st_nlink!=1:raise ValueError('image path')
 raw=p.read_bytes()
 if len(raw)!=items[0]['size'] or hashlib.sha256(raw).hexdigest()!=items[0]['sha256']:raise ValueError('artifact hash')
 from PIL import Image
 Image.MAX_IMAGE_PIXELS=16*1024*1024
 with Image.open(io.BytesIO(raw)) as image:
  if image.width>4096 or image.height>4096 or image.format not in {'PNG','JPEG'}:raise ValueError('image dimensions/type')
  image.thumbnail((512,512))
  rgba=image.convert('RGBA');rgb=Image.new('RGB',rgba.size,(28,28,28));rgb.paste(rgba,mask=rgba.getchannel('A'))
  for quality in [80,65,50,35,20]:
   buffer=io.BytesIO();rgb.save(buffer,format='JPEG',quality=quality,optimize=True);data=buffer.getvalue()
   if len(data)<=36000:break
  else:raise ValueError('preview quota')
  return {'mavka_media_v1':True,'mimeType':'image/jpeg','data':base64.b64encode(data).decode(),'sha256':items[0]['sha256'],'job_id':job,'name':name,'width':rgb.width,'height':rgb.height}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--job',required=True);p.add_argument('--name',required=True);a=p.parse_args()
 print(json.dumps(preview(a.job,a.name),separators=(',',':')))
