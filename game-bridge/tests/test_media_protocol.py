import base64,copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'deploy'))
from game_media_protocol import adapt
class MediaTests(unittest.TestCase):
 def setUp(self):
  self.request={'method':'tools/call','params':{'name':'vm_exec','arguments':{'command':'python3 /opt/mavka-game-bridge/current/media.py --job fixture --name render.png'}}}
  self.image={'mavka_media_v1':True,'mimeType':'image/jpeg','data':base64.b64encode(b'\xff\xd8fixture\xff\xd9').decode(),'sha256':'a'*64,'job_id':'fixture','name':'render.png','width':32,'height':32}
 def response(self,image=None):return {'result':{'isError':False,'content':[{'type':'text','text':json.dumps({'exit_code':0,'truncated':False,'timed_out':False,'output':json.dumps(image or self.image)})}]}}
 def test_promotes_only_scoped_image(self):
  response=self.response();out=adapt(self.request,response)
  self.assertEqual(out['result']['content'][1]['type'],'image');self.assertEqual(response['result']['content'][0]['type'],'text')
 def test_other_commands_unchanged(self):
  for cmd in ['cat /etc/passwd','python3 /opt/mavka-game-bridge/current/media.py --job ../escape --name render.png','python3 /opt/mavka-game-bridge/current/media.py --job fixture --name render.png; id']:
   req=copy.deepcopy(self.request);req['params']['arguments']['command']=cmd;r=self.response();self.assertIs(adapt(req,r),r)
 def test_wrong_metadata_and_quota(self):
  for change in [{'job_id':'other'},{'mimeType':'text/html'},{'data':'invalid'},{'width':9999},{'data':base64.b64encode(b'\xff\xd8'+b'x'*36000+b'\xff\xd9').decode()}]:
   image=dict(self.image,**change);r=self.response(image);self.assertIs(adapt(self.request,r),r)
