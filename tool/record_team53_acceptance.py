"""Record scoped team initialization and build a credential-free delivery packager."""
import io,json,subprocess
from pathlib import Path
from PIL import Image,ImageChops

root=Path(__file__).resolve().parents[1];folder=root/'docs/product/linesight/acceptance/team53-batch'
assert '+448: All tests passed!' in (root/'.artifact-work/team53-full.log').read_text(encoding='utf-8-sig')
assert 'No issues found!' in (root/'.artifact-work/team53-analyze.log').read_text(encoding='utf-8-sig')
backend=(root/'.artifact-work/team53-backend.log').read_text(encoding='utf-8-sig')
assert 'Ran 93 tests' in backend and '\nOK\n' in backend
live=json.loads((folder/'live-api.json').read_text(encoding='utf-8'))
assert len(live['members'])==12 and live['unique_portraits']==12 and live['registration_page_entry_absent'] and live['direct_provider_registration_denied']
initial=json.loads((folder/'initialization.json').read_text(encoding='utf-8'))
assert initial['members']==12 and initial['tasks']==24 and initial['checks']==20 and initial['audit_events']==124
deploy=json.loads((folder/'deployment.json').read_text())
assert deploy['existing_rows_preserved'] and deploy['api_health']
assert len(list((folder/'png').glob('*.png')))==5
assert 'checkcheck' in (folder/'ui/317-checkcheck-workbench-emulator.xml').read_text(encoding='utf-8')
assert '顾承泽' in (folder/'ui/318-checkcheck-owner-profile-emulator.xml').read_text(encoding='utf-8')
assert '团队主管' in (folder/'ui/320-checkcheck-staff-more-emulator.xml').read_text(encoding='utf-8')
assert '20 全部' in (folder/'ui/321-checkcheck-inspection-records-emulator.xml').read_text(encoding='utf-8')
audit=[]
for name in subprocess.check_output(['git','diff','--name-only','--','*.png'],cwd=root,text=True).splitlines():
    before=Image.open(io.BytesIO(subprocess.check_output(['git','show','HEAD:'+name],cwd=root))).convert('RGB');after=Image.open(root/name).convert('RGB')
    bbox=ImageChops.difference(before,after).getbbox()
    assert bbox and bbox[2]-bbox[0]<=25 and bbox[3]-bbox[1]<=15,(name,bbox)
    audit.append({'file':name,'changed_bbox':bbox,'change':'displayed version only'})
(folder/'golden-change-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
report={'version':'1.1.53+8077','flutter_full_tests_passed':448,'backend_tests_passed':93,'flutter_analyze_clean':True,'team_initialization_verified':True,'all_12_pkce_login_verified':True,'existing_7_passwords_unchanged':True,'registration_closed':True,'native_default_team_and_portraits_verified':True,'native_track':'preview','native_all_roles_verified':False,'physical_devices_verified':False,'new_png':5,'tasks':24,'inspection_records':20,'audit_events':124,'shared_workspace_id':30,'seeded_history_provenance_preserved':True}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
package=(root/'tool/package_callback52_delivery.py').read_text(encoding='utf-8')
package=package.replace('callback52-batch','team53-batch').replace("validation['native_password_login_verified']","validation['team_initialization_verified']").replace('445','448').replace('329','334').replace('callback52-{track}','team53-{track}').replace('1.1.52','1.1.53').replace('8076','8077')
(root/'tool/package_team53_delivery.py').write_text(package,encoding='utf-8')
print(json.dumps(report))
