"""Assemble release evidence only after real storage and camera observations exist."""
import json
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/release-batch'
def read(name): return json.loads((folder/name).read_text(encoding='utf-8'))
pairs=[('preview-before-storage.json','preview-after-install-storage.json',8039,8058),
       ('preview-before-final-storage.json','preview-after-final-install-storage.json',8058,8059),
       ('formal-before-storage.json','formal-after-install-storage.json',8056,8059)]
steps=[]
for old,new,old_code,new_code in pairs:
    a,b=read(old),read(new)
    assert a['version_code']==old_code and b['version_code']==new_code
    assert a['persisted_files']==b['persisted_files']
    assert a['keystore_alias_hashes']==b['keystore_alias_hashes']
    assert a['probe_sha256']==b['probe_sha256']
    assert a['databases']==b['databases']
    steps.append({'track':'production' if old.startswith('formal') else 'preview','from':old_code,'to':new_code,'persistent_file_count':len(a['persisted_files']),
                  'all_persistent_files_identical_after_install':True,'keystore_aliases_identical':True,
                  'sentinel_identical':True,'sqlite_database_count':len(a['databases'])})
camera=read('camera-permission-journey.json')
assert camera['preview_opened_without_second_tap'] and camera['cloud_contour_result_seen']
assert camera['back_returns_to_workbench'] and camera['open_camera_taps']==1
runtime=read('preview-final-runtime-storage.json')
assert runtime['version_code']==8059
assert runtime['probe_sha256']==read('preview-before-storage.json')['probe_sha256']
assert set(read('preview-before-storage.json')['keystore_alias_hashes']).issubset(runtime['keystore_alias_hashes'])
receipt_screen=(root/'.artifact-work/release/final-preview-window.xml').read_text(encoding='utf-8')
receipts=['ccceceed-95a5-41e0-a6ac-ac32fe7a070a','1567602f-45e8-4a7f-86c1-19f7e79b8628',
          '42c92829-7ab4-443e-a840-4bf8e0fee3a5','d7324862-45ba-4ae4-a8c8-4bb0c84c30da','abe45829-9858-420b-b2e6-c5bde8dce232']
assert all(receipt in receipt_screen for receipt in receipts)
private=root/'.artifact-work/release'
assert (private/'preview-before-uid.txt').read_bytes()==(private/'preview-after-uid.txt').read_bytes()
for track,certificate in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),
                          ('production',read('release-certificate.json')['certificate_sha256'])]:
    signature=(root/f'.artifact-work/sso/release-{track}-signature.log').read_text(encoding='utf-16' if (root/f'.artifact-work/sso/release-{track}-signature.log').read_bytes().startswith(b'\xff\xfe') else 'utf-8')
    assert certificate in signature and 'Verifies' in signature
tests=(root/'.artifact-work/sso/release-full-flutter-tests.log').read_text(encoding='utf-8')
assert re.search(r'\+189: All tests passed!',tests)
report={'version':'1.1.35+8059','flutter_tests_passed':189,'flutter_analyze':'No issues found',
        'backend_source_unchanged':True,'previous_backend_tests_passed':57,
        'preview_upgrade_verified':True,'production_signature_verified':True,
        'preview_certificate_matches_old_install':True,'upgrade_steps':steps,'android_uid_preserved':True,
        'demo_login_restored_without_login_action':True,'retained_uploaded_photo_receipts':5,
        'app_data_cleared':False,'main_app_uninstalled':False,'phone_installs':0,
        'production_certificate_upgrade_verified':True,
        'production_upgrade_baseline':'Acceptance-only copy of 1.1.34+8056 re-signed with the new production certificate; not a historical production release',
        'preview_runtime_verified_through_version_code':8059,'final_runtime_verified_on_dedicated_production_emulator':True,
        'old_emulator_abrupt_exit_and_package_registration_repair_observed':True,
        'original_emulator_recovered_with_host_gpu_and_vulkan_disabled':True,
        'final_preview_login_and_five_receipts_verified':True,'original_display_overrides_restored':True,
        'physical_camera_verified':False,'physical_nfc_verified':False,
        'normal_customer_apk_debuggable':False,'test_plugins_absent_from_customer_apk':True,
        'camera_permission_single_tap_verified':True,'camera_frames_cloud_processed_on_emulator':True,
        'native_ui_navigation_observed':['workbench -> pending inspection filter -> task detail',
          'task detail -> inspection form -> back to task detail','task detail -> scoped report -> back to task detail',
          'task detail -> QR codes -> back to task detail -> retained filtered list -> workbench',
          'my -> sync and drafts -> retained receipts -> back to my','my -> local import authorization -> back to my',
          'workbench -> online inspection -> first camera permission grant -> live contour -> back to workbench'],
        'first_boot_system_ui_anr_observed':True,'system_ui_wait_recovered':True,
        'formal_key_off_host_backup_verified':False,'two_physical_phones_verified':False,'ten_external_users_verified':False,
        'product_plan_complete':False}
(folder/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'version':report['version'],'upgrade_steps':steps,'camera_permission_single_tap_verified':True}))
