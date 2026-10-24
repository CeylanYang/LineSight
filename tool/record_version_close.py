"""Record only checks actually completed for this version."""
import io
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageChops

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/section-focus-batch'
assert '+445: All tests passed!' in (root/'.artifact-work/native51-full.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/native51-analyze.log').read_text(encoding='utf-8-sig')
assert not subprocess.check_output(['git','diff','--','backend'],cwd=root,text=True).strip()
audit=[]
for name in subprocess.check_output(['git','diff','--name-only','--','*.png'],cwd=root,text=True).splitlines():
    before=Image.open(io.BytesIO(subprocess.check_output(['git','show','HEAD:'+name],cwd=root))).convert('RGB')
    after=Image.open(root/name).convert('RGB')
    bbox=ImageChops.difference(before,after).getbbox()
    assert bbox and bbox[2]-bbox[0]<=25 and bbox[3]-bbox[1]<=15,(name,bbox)
    audit.append({'file':name,'changed_bbox':bbox,'change':'displayed version only'})
(folder/'golden-change-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
report={'version':'1.1.51+8075','flutter_full_tests_passed':445,'new_behavior_tests':3,
 'flutter_analyze_clean':True,'section_focus_verified':True,'backend_source_unchanged':True,
 'previous_backend_tests_passed':87,'backend_evidence':'../assignment-batch/validation.json',
 'native_business_flow_version':'1.1.50+8074','native_business_flow_png':18,
 'native_final_apk_verified':False,'physical_devices_verified':False,
 'delivery_goal_complete':True,'goal_scope':'Current usable version and evidence handoff, per user closeout request; remaining work retained.',
 'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
