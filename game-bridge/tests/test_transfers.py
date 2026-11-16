import base64,hashlib,json,unittest
import test_gateway
from transfers import CHUNK,operate
class TransferTests(unittest.TestCase):
 setUp=test_gateway.Tests.setUp
 tearDown=test_gateway.Tests.tearDown
 def request(self,d,role=None,job=None):
  with self.b.db() as c:return operate(self.b,c,'owner' if role is None else 'pc',role or self.owner,d,job)
 def test_roundtrip_chunks_and_immutability(self):
  raw=b'a'*(CHUNK+9);digest=hashlib.sha256(raw).hexdigest();project='b'*32
  self.request({'op':'init','sha256':digest,'size':len(raw),'device_id':'pc','project_id':project})
  with self.assertRaises(ValueError):self.request({'op':'complete','sha256':digest})
  for i in range(2):
   part=raw[i*CHUNK:(i+1)*CHUNK];d={'op':'chunk','sha256':digest,'index':i,'chunk_sha256':hashlib.sha256(part).hexdigest(),'content':base64.b64encode(part).decode()}
   self.request(d);self.request(d)
  self.assertTrue(self.request({'op':'complete','sha256':digest})['complete'])
  out=b''
  for i in range(2):out+=base64.b64decode(self.request({'op':'download','sha256':digest,'index':i})['content'])
  self.assertEqual(raw,out)
  with self.assertRaises(ValueError):self.request({'op':'chunk','sha256':digest,'index':0,'content':''})
 def test_project_device_binding(self):
  digest=hashlib.sha256(b'abc').hexdigest();project='b'*32
  self.request({'op':'init','sha256':digest,'size':3,'device_id':'pc','project_id':project})
  for args in [{'project_id':'c'*32,'package_sha256':digest},{'project_id':project,'package_sha256':'a'*64}]:
   job={'state':'running','body':json.dumps({'action':'files.pull','arguments':args})}
   with self.assertRaises(PermissionError):self.request({'op':'download','sha256':digest,'index':0},self.device,job)
 def test_hash_quota_bad_index(self):
  for digest,size in [('../escape',3),('a'*64,256*1024*1024+1)]:
   with self.assertRaises(ValueError):self.request({'op':'init','sha256':digest,'size':size,'device_id':'pc','project_id':'b'*32})
  digest=hashlib.sha256(b'abc').hexdigest();self.request({'op':'init','sha256':digest,'size':3,'device_id':'pc','project_id':'b'*32})
  with self.assertRaises(ValueError):self.request({'op':'chunk','sha256':digest,'index':2,'content':''})
  with self.assertRaises(ValueError):self.request({'op':'chunk','sha256':digest,'index':0,'content':base64.b64encode(b'abc').decode(),'chunk_sha256':'a'*64})
