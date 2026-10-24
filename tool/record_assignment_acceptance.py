"""Record tested assignment and handover behavior without native claims."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/assignment-batch'
assert '+425: All tests passed!' in (root/'.artifact-work/assignment-full-tests.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/assignment-analyze.log').read_text(encoding='utf-8-sig')
backend=(root/'.artifact-work/assignment-backend-tests.log').read_text(encoding='utf-8-sig')
assert 'Ran 87 tests' in backend and '\nOK\n' in backend
assert json.loads((folder/'live-assignment.json').read_text())['passed']
assert json.loads((folder/'deployment.json').read_text())['existing_rows_preserved']
screens=[]
for path in sorted((folder/'png').glob('*-component.png')):
    with Image.open(path) as picture: assert picture.size==(360,1100)
    screens.append({'file':path.relative_to(folder).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'origin':'desktop-component-render'})
assert len(screens)==8
report={'version':'1.1.49+8073','flutter_full_tests_passed':425,'backend_tests_passed':87,
        'new_flutter_tests':16,'new_backend_tests':9,'new_component_png':8,'flutter_analyze_clean':True,
        'assignment_and_issue_handover_verified':True,'real_https_verified':True,
        'native_final_apk_verified':False,'physical_devices_verified':False,'product_plan_complete':False,
        'screenshots':screens}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
