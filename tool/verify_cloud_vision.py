"""HTTPS acceptance using photo-derived buffers, not a physical phone camera."""
import base64
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request,urlopen
import cv2
import numpy as np

folder=Path('docs/product/linesight/acceptance/vision-batch')
config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
oidc=config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/'
with urlopen(Request(oidc+'token',data=urlencode({'grant_type':'password','client_id':'linesight-demo','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as response:
    tokens=json.load(response)

def call(path,body=None,authenticated=True):
    headers={'Content-Type':'application/json'}
    if authenticated: headers['Authorization']='Bearer '+tokens['access_token']
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,data=json.dumps(body).encode() if body is not None else None,headers=headers),timeout=30) as response:
            raw=response.read()
            return response.status,json.loads(raw) if response.headers.get_content_type()=='application/json' else raw,response.headers
    except HTTPError as error:
        return error.code,json.loads(error.read()),error.headers

try:
    _,me,_=call('auth/me/');assert me['is_demo']
    workspace=me['home_workspace_id'];base=f'workspaces/{workspace}/'
    codes=json.loads((folder/'generated-assets.json').read_text())['codes']
    results={}
    for name in ['batch','piece']:
        status,data,_=call(base+'trace/lookup/?'+urlencode({'code':codes[name]}))
        assert status==200 and len(data['jobs'])==1,data
        assert data['jobs'][0]['status']=='closed'
        if name=='piece':assert data['jobs'][0]['piece_verdict']=='pass'
        (folder/f'live-{name}.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        results[name+'_lookup']=True
    source=cv2.imread(str(folder/'reference-original-source.png'))
    source=cv2.resize(source,(320,240));bgra=cv2.cvtColor(source,cv2.COLOR_BGR2BGRA)
    payload={'width':320,'height':240,'format':'bgra8888','rotation':0,'planes':[{'bytes':base64.b64encode(bgra.tobytes()).decode(),'row_stride':1280,'pixel_stride':4}]}
    status,data,headers=call(base+'vision/frame/',payload)
    assert status==200 and data['algorithm']=='mean-shift-canny-zhang-suen-v1',data
    assert headers['Cache-Control']=='no-store'
    edge=base64.b64decode(data['edge_png']);assert edge.startswith(b'\x89PNG')
    pixels=cv2.imdecode(np.frombuffer(edge,dtype=np.uint8),cv2.IMREAD_COLOR)
    assert np.count_nonzero(np.any(pixels!=255,axis=2))>100
    (folder/'cloud-frame-contour-processed.png').write_bytes(edge)
    (folder/'cloud-frame-original-source.png').write_bytes(base64.b64decode(data['original_png']))
    results.update({'https_frame':True,'frame_source':'existing reference photo converted to BGRA; no physical camera','processing_ms':data['processing_ms'],'algorithm':data['algorithm'],'frame_not_cached':True})
    status,_,_=call(base+'vision/frame/',{},authenticated=False);assert status==401;results['anonymous_frame_status']=status
    status,_,_=call('workspaces/999999/vision/frame/',{});assert status==404;results['foreign_frame_status']=status
    status,_,_=call('workspaces/999999/trace/lookup/?code='+codes['piece']);assert status==404;results['foreign_lookup_status']=status
    # Reading an older stored preview exercises the production lazy migration.
    job=codes['task'].rsplit('/',1)[1]
    _,detail,_=call(base+f'jobs/{job}/')
    photo=detail['evidence'][0]
    status,preview,_=call(base+f"jobs/{job}/evidence/{photo['id']}/preview/")
    assert status==200 and preview.startswith(b'\x89PNG');results['existing_evidence_preview']=True
    (folder/'live-api.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(results,ensure_ascii=False))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()
