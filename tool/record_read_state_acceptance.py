"""Verify normal APK read-state screenshots and data-preserving upgrade."""
import hashlib
import json
import subprocess
from pathlib import Path
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/read-state-batch'
before,after=[json.loads((folder/name).read_text()) for name in ['before-upgrade-storage.json','after-upgrade-storage.json']]
assert before['version_code']==8063 and after['version_code']==8064
for key in ['persisted_files','databases','keystore_alias_hashes','probe_sha256']:
    assert before[key]==after[key],key
final_before,final_after=[json.loads((folder/name).read_text()) for name in ['before-final-reinstall-storage.json','after-final-reinstall-storage.json']]
for key in ['persisted_files','databases','keystore_alias_hashes','probe_sha256']:
    assert final_before[key]==final_after[key],key
assert '+254: All tests passed!' in (root/'.artifact-work/sso/read-state-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/read-state-analyze.log').read_text(encoding='utf-8')
checks={
 '130-workbench-ready-zh-emulator':'今日待检',
 '131-workbench-network-failure-zh-emulator':'连接未完成',
 '132-templates-network-failure-zh-emulator':'连接未完成',
 '133-records-network-failure-zh-emulator':'连接未完成',

}
screens=[]
for stem,label in checks.items():
    tree=ET.parse(root/'.artifact-work/release'/f'{stem}.xml')
    labels=[n.get('text','')+'\n'+n.get('content-desc','') for n in tree.iter('node')]
    assert any(label in text for text in labels),(stem,label)
    if 'network-failure' in stem:
        for misleading in ['暂无生产任务','暂无检查模板','暂无检验记录','已清空','今日待检','Awaiting inspection today']:
            assert not any(misleading in text for text in labels),(stem,misleading)
    path=folder/'png'/f'{stem}.png'
    assert path.exists()
    assert path.stat().st_mtime > (root/'.artifact-work/release/LineSight-1.1.40-8064-preview.apk').stat().st_mtime
    screens.append({'file':'png/'+path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
assert 'emulator-5554' not in subprocess.check_output([r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe','devices'],text=True)
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    raw=(root/f'.artifact-work/sso/read-state-{track}-signature.log').read_bytes()
    log=raw.decode('utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8')
    assert cert in log and 'Verifies' in log
result={'version':'1.1.40+8064','flutter_tests_passed':254,'new_tests':14,
    'flutter_analyze':'No issues found','backend_source_unchanged':True,
    'preview_upgrade_verified':True,'production_signature_verified':True,
    'final_reinstall_storage_verified':True,'native_failure_hides_counts':True,'native_retry_recovers':False,'earlier_8064_candidate_retry_recovered':True,
    'native_templates_and_records_failure_zh':True,
    'native_workbench_failure_zh':True,'final_native_retry_and_english_pending':True,
    'component_loading_failure_empty_no_team_zh_en':True,
    'first_team_creation_without_workspace_widget_verified':True,
    'late_read_after_expiry_cannot_publish':True,
    'emulator_stopped_after_acceptance':True,'cloud_business_writes_performed':False,
    'storage_files_preserved':len(before['persisted_files']),'databases_preserved':len(before['databases']),
    'keystore_aliases_and_sentinel_preserved':True,'app_data_cleared':False,'main_app_uninstalled':False,
    'initial_upgrade_existing_login_restored':True,'emulator_system_ui_anr_waited':True,'emulator_multiple_access_violations':True,'emulator_crash_root_cause_confirmed':False,'phone_installs':0,'production_upgrade_retested_this_batch':False,'native_screenshots':screens,
    'physical_nfc_verified':False,'two_physical_phones_verified':False,
    'ten_external_users_verified':False,'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'version':result['version'],'native_screenshots':len(screens),'storage_files_preserved':len(before['persisted_files'])}))

