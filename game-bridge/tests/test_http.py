import json,secrets,threading,time,urllib.request,urllib.error,unittest
import test_gateway
from bridge import Handler,BoundedServer,signature,encoded

class HTTP(unittest.TestCase):
 setUp=test_gateway.Tests.setUp
 tearDown=test_gateway.Tests.tearDown
 def test_http_auth_and_quota(self):
  s=BoundedServer(('127.0.0.1',0),Handler);s.bridge=self.b;s.allowed=['127.0.0.1'];t=threading.Thread(target=s.serve_forever,daemon=True);t.start()
  url='http://127.0.0.1:'+str(s.server_port)
  try:
   with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(url+'/v1/status')
   self.assertEqual(e.exception.code,403)
   e.exception.close()
   stamp=str(int(time.time()));nonce=secrets.token_hex(16)
   h={'X-Principal':'owner','X-Time':stamp,'X-Nonce':nonce,'X-Signature':signature(self.key,'GET','/v1/status',stamp,nonce,b'')}
   r=urllib.request.Request(url+'/v1/status',headers=h)
   with urllib.request.urlopen(r) as response:self.assertEqual(json.load(response)['version'],'1.1.0')
   with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(r)
   self.assertEqual(e.exception.code,403)
   e.exception.close()
   r=urllib.request.Request(url+'/v1/jobs',data=b'',headers={'Content-Length':str(13*1024*1024)})
   with self.assertRaises(urllib.error.HTTPError) as e:urllib.request.urlopen(r)
   self.assertEqual(e.exception.code,400)
   e.exception.close()
  finally:s.shutdown();s.server_close();t.join()
