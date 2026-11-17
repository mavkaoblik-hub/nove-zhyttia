"""Optional existing Oracle MCP HTTP adapter: promote one scoped media CLI response."""
import base64,binascii,copy,json,re,shlex
def adapt(request,response):
 try:
  if request.get('method')!='tools/call' or request['params'].get('name')!='vm_exec':return response
  argv=shlex.split(request['params']['arguments']['command'])
  if len(argv)!=6 or argv[0] not in {'python3','/usr/bin/python3'} or argv[1]!='/opt/mavka-game-bridge/current/media.py' or argv[2]!='--job' or argv[4]!='--name':return response
  if not re.fullmatch('[a-zA-Z0-9_-]{1,80}',argv[3]) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,80}\.(png|jpg|jpeg)',argv[5]):return response
  result=response['result']
  if result.get('isError') or len(result['content'])!=1 or result['content'][0]['type']!='text':return response
  value=json.loads(result['content'][0]['text'])
  if type(value.get('exit_code')) is not int or value['exit_code']!=0 or value.get('truncated') or value.get('timed_out'):return response
  image=json.loads(value['output'])
  if image.get('mavka_media_v1') is not True or image.get('mimeType')!='image/jpeg' or image.get('job_id')!=argv[3] or image.get('name')!=argv[5] or not re.fullmatch('[a-f0-9]{64}',image.get('sha256','')):return response
  if type(image.get('width')) is not int or type(image.get('height')) is not int or not 1<=image['width']<=512 or not 1<=image['height']<=512:return response
  raw=base64.b64decode(image['data'],validate=True)
  if not 4<=len(raw)<=36000 or not raw.startswith(b'\xff\xd8') or not raw.endswith(b'\xff\xd9'):return response
  converted=copy.deepcopy(response)
  metadata={k:v for k,v in image.items() if k not in {'data','mavka_media_v1'}}
  converted['result']['content']=[{'type':'text','text':json.dumps(metadata)},{'type':'image','mimeType':'image/jpeg','data':image['data']}]
  return converted
 except (KeyError,TypeError,ValueError,binascii.Error):return response
