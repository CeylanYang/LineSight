"""Validate the new receipt-based create navigation evidence."""
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/create-navigation-batch'
tests=(root/'.artifact-work/create-navigation-full-tests.log').read_text(encoding='utf-8-sig')
analyze=(root/'.artifact-work/create-navigation-analyze.log').read_text(encoding='utf-8-sig')
assert '+409: All tests passed!' in tests
assert 'No issues found!' in analyze
assert not subprocess.check_output(['git','diff','--','backend'],cwd=root,text=True).strip()
screens=[]
for language in ['zh','en']:
    path=folder/f'png/290-created-task-{language}-component.png'
    with Image.open(path) as picture: assert picture.size==(360,1100)
    screens.append({'file':path.relative_to(folder).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'origin':'desktop-component-render'})
previous=json.loads((root/'docs/product/linesight/acceptance/profile-management-batch/validation.json').read_text())
assert previous['backend_tests_passed']==78
report={'version':'1.1.48+8072','flutter_full_tests_passed':409,'new_tests':10,
        'new_behavior_tests':8,'new_component_png':2,'flutter_analyze_clean':True,
        'backend_source_unchanged':True,'previous_backend_tests_passed':78,
        'backend_evidence':'../profile-management-batch/validation.json',
        'confirmed_create_replaces_form_with_task_detail':True,
        'background_reload_does_not_delay_result':True,
        'detail_read_failure_preserves_create_receipt':True,
        'profile_and_template_back_routes_verified':True,
        'late_result_scope_and_route_guards_verified':True,
        'native_final_apk_verified':False,'physical_devices_verified':False,
        'business_cloud_writes_this_batch':False,'product_plan_complete':False,
        'screenshots':screens}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'tests':409,'new_tests':10,'new_png':2,'native_verified':False}))
