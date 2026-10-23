"""Record the conflict batch after actual native and cloud checks."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/conflict-batch'
def read(name): return json.loads((folder/name).read_text(encoding='utf-8'))
a,b=read('before-upgrade-storage.json'),read('after-upgrade-storage.json')
assert a['version_code']==8059 and b['version_code']==8060
for field in ['persisted_files','keystore_alias_hashes','probe_sha256','databases']:
    assert a[field]==b[field],field
final_before,final_after=read('before-final-install-storage.json'),read('after-final-install-storage.json')
for field in ['persisted_files','keystore_alias_hashes','probe_sha256','databases']:
    assert final_before[field]==final_after[field],field
cloud=read('live-conflict.json')
assert cloud['verified_after_android'] and cloud['only_one_inspection'] and cloud['stale_request_status']==409
journey=read('native-journey.json')
assert all(journey[key] for key in ['comparison_visible','latest_task_closed','back_keeps_draft','account_card_opens_profile','profile_back_keeps_my','original_display_restored'])
assert '+199: All tests passed!' in (root/'.artifact-work/sso/conflict-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/conflict-analyze.log').read_text(encoding='utf-8')
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    raw=(root/f'.artifact-work/sso/conflict-{track}-signature.log').read_bytes()
    signature=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8')
    assert cert in signature and 'Verifies' in signature
report={'version':'1.1.36+8060','flutter_tests_passed':199,'flutter_analyze':'No issues found',
        'backend_source_unchanged':True,'previous_backend_tests_passed':57,
        'preview_upgrade_verified':True,'production_signature_verified':True,
        'preserved_file_count':len(a['persisted_files']),'preserved_database_count':len(a['databases']),
        'final_artifact_reinstall_storage_verified':True,
        'keystore_and_sentinel_preserved':True,'live_conflict_verified':True,'live_conflict_response':409,
        'live_conflict_inspection_count':1,'native_journey':journey,
        'normal_customer_apk_debuggable':False,'test_plugins_absent_from_customer_apk':True,
        'app_data_cleared':False,'main_app_uninstalled':False,'phone_installs':0,
        'old_demo_session_required_reauthentication':True,
        'demo_refresh_http_tests_passed':3,'fresh_demo_login_verified':True,
        'expired_access_token_successful_native_refresh_retested':False,
        'production_upgrade_retested_this_batch':False,'physical_camera_verified':False,
        'physical_nfc_verified':False,'two_physical_phones_verified':False,'ten_external_users_verified':False,
        'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'version':report['version'],'preserved_files':report['preserved_file_count'],'live_conflict_verified':True}))
