"""Read back the Android demo import and recovered evidence over real HTTPS."""
import io
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from PIL import Image

folder = Path('docs/product/linesight/acceptance/sync-batch')
android = json.loads((folder/'android-journey.json').read_text(encoding='utf-8'))
assert android.get('diagnostics_redacted_fields_verified') is True
config = json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
oidc = config['LINESIGHT_OIDC_ISSUER']+'/protocol/openid-connect/'
with urlopen(Request(oidc+'token',data=urlencode({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}).encode()),timeout=25) as response:
    tokens = json.load(response)

def call(path,body=None,authenticated=True,binary=False):
    headers = {'Authorization':'Bearer '+tokens['access_token']} if authenticated else {}
    if body is not None: headers['Content-Type']='application/json'
    try:
        with urlopen(Request(config['LINESIGHT_API_BASE_URL']+path,headers=headers,data=json.dumps(body).encode() if body is not None else None),timeout=30) as response:
            return response.status,response.read() if binary else json.load(response)
    except HTTPError as failure:
        return failure.code,None
try:
    _,me=call('auth/me/'); assert me['is_demo']
    workspace=android['workspace_id']; assert workspace==me['home_workspace_id']
    base=f'workspaces/{workspace}/'; legacy=base+'legacy-inspections/'
    _,data=call(legacy)
    source=android['source_record_id']
    assert sum(row['id']==source for row in data['records'])==1
    assert not any(row['id']==source+'-sample' for row in data['records'])
    reviewed={'id':source+'-review','at':'2026-10-23T12:00:00Z','recipeName':'DEMO · 导入复核结果验收','serial':'LOCAL-REVIEW','passed':False,'review':'pass','sample':False}
    status,receipt=call(legacy,{'records':[reviewed]}); assert status==201
    _,repeat=call(legacy,{'records':[reviewed]}); assert repeat=={'imported':0,'skipped':1}
    _,data=call(legacy)
    final=next(row for row in data['records'] if row['id']==reviewed['id'])
    assert final['passed'] is True and final['original_passed'] is False and final['review']=='pass'
    job_id=android['job_id']; _,job=call(base+f'jobs/{job_id}/')
    assert len(job['evidence'])==1
    evidence=job['evidence'][0]; assert evidence['stage']=='inspection'
    status,image=call(base+f"jobs/{job_id}/evidence/{evidence['id']}/original/",binary=True)
    assert status==200
    with Image.open(io.BytesIO(image)) as photo:
        photo.load(); size=photo.size; image_format=photo.format
        assert image_format in ('PNG','JPEG') and size[0]*size[1]<=16000000
    anonymous,_=call(legacy,authenticated=False); assert anonymous in (401,403)
    denied,_=call(f'workspaces/999999/jobs/{job_id}/'); assert denied==404
    output={'demo_only':True,'source_record_id':source,'source_record_occurrences':1,'sample_excluded':True,'repeat_import_skipped':1,'original_and_review_outcomes_preserved':True,'job_id':job_id,'evidence_id':evidence['id'],'recovered_image_format':image_format,'recovered_image_dimensions':size,'actual_transport_progress_samples':android['actual_transport_progress_samples'],'diagnostics_redacted_fields_verified':android.get('diagnostics_redacted_fields_verified') is True,'anonymous_status':anonymous,'foreign_workspace_status':denied}
    (folder/'live-api.json').write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(output))
finally:
    urlopen(Request(oidc+'logout',data=urlencode({'client_id':'linesight-demo','refresh_token':tokens['refresh_token']}).encode()),timeout=20).close()
