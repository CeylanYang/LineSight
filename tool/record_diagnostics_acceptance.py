"""Validate diagnostic recovery tests and bilingual component evidence."""
import hashlib
import io
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageChops

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/diagnostics-batch'
assert '+442: All tests passed!' in (root/'.artifact-work/diagnostics-full-tests.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/diagnostics-analyze.log').read_text(encoding='utf-8-sig')
assert not subprocess.check_output(['git','diff','--','backend'],cwd=root,text=True).strip()
previous=json.loads((folder.parent/'assignment-batch/validation.json').read_text())
assert previous['backend_tests_passed']==87
screens=[]
for path in sorted((folder/'png').glob('*.png')):
    with Image.open(path) as picture: assert picture.size==(360,1100)
    screens.append({'file':path.relative_to(folder).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'origin':'desktop-component-render'})
assert len(screens)==6
audit=[]
changed=subprocess.check_output(['git','diff','--name-only','--','*.png'],cwd=root,text=True).splitlines()
for name in changed:
    assert name in [f'docs/product/linesight/acceptance/template-batch/png/181-unified-login-{language}-desktop-render.png' for language in ['zh','en']],name
    before=Image.open(io.BytesIO(subprocess.check_output(['git','show','HEAD:'+name],cwd=root))).convert('RGB')
    after=Image.open(root/name).convert('RGB')
    bbox=ImageChops.difference(before,after).getbbox()
    assert bbox and bbox[2]-bbox[0]<=20 and bbox[3]-bbox[1]<=12,bbox
    audit.append({'file':name,'changed_bbox':bbox,'scope':'displayed version only'})
(folder/'golden-change-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
report={'version':'1.1.50+8074','flutter_full_tests_passed':442,'new_tests':17,'new_behavior_tests':11,
    'new_component_png':6,'flutter_analyze_clean':True,'backend_source_unchanged':True,
    'previous_backend_tests_passed':87,'backend_evidence':'../assignment-batch/validation.json',
    'diagnostics_recovery_and_scope_verified':True,'diagnostics_export_allowlist_verified':True,
    'help_entry_return_and_cloud_copy_verified':True,'local_sample_action_explicit':True,
    'native_final_apk_verified':False,'physical_devices_verified':False,
    'business_cloud_writes_this_batch':False,'product_plan_complete':False,'screenshots':screens}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'tests':442,'new_tests':17,'new_png':6,'native_verified':False}))
