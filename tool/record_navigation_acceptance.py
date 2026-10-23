"""Validate normal APK navigation evidence and data-preserving upgrade."""
import hashlib
import json
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/navigation-batch'
before,after=[json.loads((folder/name).read_text()) for name in ['before-upgrade-storage.json','after-upgrade-storage.json']]
assert before['version_code']==8062 and after['version_code']==8063
for key in ['persisted_files','databases','keystore_alias_hashes','probe_sha256']:
    assert before[key]==after[key],key
final_before,final_after=[json.loads((folder/name).read_text()) for name in ['before-final-reinstall-storage.json','after-final-reinstall-storage.json']]
for key in ['persisted_files','databases','keystore_alias_hashes','probe_sha256']:
    assert final_before[key]==final_after[key],key
assert '+240: All tests passed!' in (root/'.artifact-work/sso/navigation-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/navigation-analyze.log').read_text(encoding='utf-8')
checks={
 '120-account-secondary-emulator':'账户与安全',
 '121-back-to-profile-emulator':'团队与账户',
 '122-system-back-workbench-emulator':'今日待检',
 '123-trace-unavailable-zh-emulator':'记录暂不可访问',
 '124-explicit-workbench-zh-emulator':'今日待检',
 '125-trace-unavailable-en-emulator':'Record unavailable',
 '126-explicit-workbench-en-emulator':'Awaiting inspection today',
 '127-version-footer-emulator':'LineSight 1.1.39',
}
screens=[]
for stem,label in checks.items():
    tree=ET.parse(root/'.artifact-work/release'/f'{stem}.xml')
    assert any(label in (n.get('text','')+'\n'+n.get('content-desc','')) for n in tree.iter('node')),(stem,label)
    path=folder/'png'/f'{stem}.png'
    assert path.exists()
    screens.append({'file':'png/'+path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
for stem,label in {'121-back-to-profile-emulator':'我的',
    '122-system-back-workbench-emulator':'工作台',
    '124-explicit-workbench-zh-emulator':'工作台',
    '126-explicit-workbench-en-emulator':'Dashboard',
    '127-version-footer-emulator':'Profile'}.items():
    tree=ET.parse(root/'.artifact-work/release'/f'{stem}.xml')
    assert any(n.get('selected')=='true' and label in [n.get('text'),n.get('content-desc')] for n in tree.iter('node')),(stem,label)
assert 'emulator-5554' not in subprocess.check_output([r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe','devices'],text=True)
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    raw=(root/f'.artifact-work/sso/navigation-{track}-signature.log').read_bytes()
    log=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8')
    assert cert in log and 'Verifies' in log
result={'version':'1.1.39+8063','flutter_tests_passed':240,'new_navigation_tests':20,
    'flutter_analyze':'No issues found','backend_source_unchanged':True,
    'preview_upgrade_verified':True,'production_signature_verified':True,
    'native_secondary_back_preserves_profile':True,'native_system_back_selects_workbench':True,
    'native_unavailable_trace_explicit_workbench_zh_en':True,
    'native_selected_destinations_verified':True,'emulator_stopped_after_acceptance':True,
    'live_missing_task_trace_used':True,'cloud_business_writes_performed':False,
    'nested_explicit_exit_matrix_widget_tests':18,
    'storage_files_preserved':len(before['persisted_files']),'databases_preserved':len(before['databases']),
    'keystore_aliases_and_sentinel_preserved':True,'app_data_cleared':False,'main_app_uninstalled':False,
    'final_reinstall_storage_verified':True,'first_upgrade_existing_login_restored':False,
    'demo_sign_in_completed_after_first_upgrade':True,'first_audit_launch_required_force_restart':True,
    'final_reinstall_demo_session_reloaded_after_network_retry':True,
    'known_issue_initial_workbench_read_failure_displays_zero_counts':True,
    'phone_installs':0,'production_upgrade_retested_this_batch':False,'screenshots':screens,
    'physical_nfc_verified':False,'two_physical_phones_verified':False,
    'ten_external_users_verified':False,'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'version':result['version'],'screenshots':len(screens),'storage_files_preserved':len(before['persisted_files'])}))
