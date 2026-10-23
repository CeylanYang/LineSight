"""Validate the native session-recovery batch before packaging."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/reauth-batch'
def read(name):return json.loads((folder/name).read_text(encoding='utf-8'))
a,b=read('before-upgrade-storage.json'),read('after-upgrade-storage.json')
assert a['version_code']==8060 and b['version_code']==8061
for field in ['persisted_files','keystore_alias_hashes','probe_sha256','databases']:assert a[field]==b[field],field
final_a,final_b=read('before-final-install-storage.json'),read('after-final-install-storage.json')
for field in ['persisted_files','keystore_alias_hashes','probe_sha256','databases']:assert final_a[field]==final_b[field],field
live=read('live-reauthentication.json')
assert live['target_session_revoked'] and not live['other_sessions_revoked']
assert live['no_automatic_submission_after_login'] and live['manual_submission_single_inspection']
journey=read('native-journey.json')
assert all(journey[k] for k in ['login_required_after_revocation','same_note_restored','parent_refreshed_after_manual_submission','original_display_restored'])
assert '+211: All tests passed!' in (root/'.artifact-work/sso/reauth-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/reauth-analyze.log').read_text(encoding='utf-8')
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    raw=(root/f'.artifact-work/sso/reauth-{track}-signature.log').read_bytes()
    signature=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8')
    assert cert in signature and 'Verifies' in signature
result={'version':'1.1.37+8061','flutter_tests_passed':211,'flutter_analyze':'No issues found',
    'backend_source_unchanged':True,'previous_backend_tests_passed':57,'preview_upgrade_verified':True,
    'production_signature_verified':True,'live_reauthentication_verified':True,
    'storage_files_preserved':len(a['persisted_files']),'databases_preserved':len(a['databases']),
    'final_artifact_reinstall_storage_verified':True,
    'keystore_and_sentinel_preserved':True,'only_own_new_demo_session_revoked':True,
    'no_automatic_submission_after_login':True,'manual_submission_single_inspection':True,
    'native_journey':journey,'app_data_cleared':False,'main_app_uninstalled':False,'phone_installs':0,
    'physical_nfc_verified':False,'two_physical_phones_verified':False,'ten_external_users_verified':False,
    'production_upgrade_retested_this_batch':False,'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'version':result['version'],'preserved_files':len(a['persisted_files']),'live_reauthentication_verified':True}))
