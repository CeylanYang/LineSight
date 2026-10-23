"""Record the completed subset of normal-APK navigation, without claiming hardware acceptance."""
import hashlib
import json
from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
folder = root / 'docs/product/linesight/acceptance/native-final-batch'
apk = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.47/LineSight-1.1.47-8071-preview.apk')
assert hashlib.sha256(apk.read_bytes()).hexdigest() == '8cace2f9b0e05c1c008bd467d9dcf6e96120eb33645a27356d3d7368c9db2a37'
launch = json.loads((root / '.artifact-work/api34-final-launch/observations.json').read_text())
assert len(launch['launches']) == 1 and launch['launches'][0]['coldWaitPassed'] and launch['launches'][0]['androidDisplayObserved']
shutil.copy2(root / '.artifact-work/api34-final-launch/observations.json', folder / 'launch.json')
checks = {
    '286-local-auth-gate-emulator': '创建此设备的管理员账户',
    '287-checklist-catalog-emulator': '3 个模板',
    '288-checklist-detail-emulator': '使用此模板创建任务',
    '289-task-from-checklist-emulator': 'Bambu Lab P2S',
}
for stem, label in checks.items():
    tree = ET.parse(folder / 'ui' / (stem + '.xml'))
    assert any(label in (node.get('text', '') + node.get('content-desc', '')) for node in tree.iter('node')), stem
images = sorted((folder / 'png').glob('*.png'))
assert len(images) == 12
contact = Image.new('RGB', (4 * 206, 3 * 436), '#e9eef6')
draw = ImageDraw.Draw(contact)
screens = []
for i, path in enumerate(images):
    with Image.open(path) as picture:
        assert picture.size == (412, 824)
        contact.paste(picture.resize((206, 412)), ((i % 4) * 206, (i // 4) * 436))
    draw.text(((i % 4) * 206 + 5, (i // 4) * 436 + 415), path.stem[:3], fill='#18243d')
    screens.append({'file': 'png/' + path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'origin': 'android-emulator-screenshot', 'ui_xml': path.stem in checks})
contact.save(root / '.artifact-work/native-final-contact.png')
negative_tests = {
    'unauthenticated_expired_identity': 'backend/collaboration/test_permissions.py',
    'viewer_403_removed_member_old_bearer': 'backend/collaboration/test_permissions.py',
    'foreign_object_ids_and_evidence_binding': 'backend/collaboration/test_object_scope.py',
    'illegal_close_reopen_duplicate_stale_version': 'backend/collaboration/test_workflow.py',
    'concurrent_writers_one_success_one_conflict': 'docs/product/linesight/acceptance/sso/live-workflow-verification.json',
}
for path in negative_tests.values():
    assert (root / path).is_file()
live = json.loads((root / negative_tests['concurrent_writers_one_success_one_conflict']).read_text())
assert live['concurrent_writers_one_success_one_conflict']
backend_log = (root / '.artifact-work/profile-management-backend-tests.log').read_text(encoding='utf-8-sig')
assert 'Ran 78 tests' in backend_log and '\nOK\n' in backend_log
report = {
    'version': '1.1.47+8071', 'apk_source_commit': 'f8b95d7d635fe6c03b330a0e9cc715c7f50b3974',
    'apk_sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'apk_rebuilt_this_batch': False,
    'new_isolated_api34_x86_64_emulator': True, 'first_install_not_upgrade_evidence': True,
    'cold_launch_passed': True, 'android_display_ms': 3854,
    'demo_secondary_login_verified': True, 'profile_picker_roundtrip_verified': True,
    'profile_source_back_route_verified': True, 'local_auth_gate_verified': True,
    'checklist_create_task_and_draft_profile_verified': True,
    'owner_profile_editor_native_verified': False, 'full_native_acceptance_complete': False,
    'emulator_process_exited_unexpectedly_after_capture': True, 'exit_cause_confirmed': False,
    'business_writes_performed': False, 'app_data_cleared': False, 'phones_installed': 0,
    'two_physical_phones_verified': False, 'physical_nfc_camera_haptics_verified': False,
    'ten_external_users_verified': False, 'smtp_password_reset_verified': False,
    'backend_negative_test_evidence': negative_tests, 'previous_backend_test_run_passed': 78,
    'screenshots': screens, 'product_plan_complete': False,
}
(folder / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'native_png': len(screens), 'full_native_acceptance_complete': False, 'negative_test_categories': len(negative_tests)}))
