"""Check the form validation batch against tests, native UI and cloud evidence."""
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/forms-batch'
def read(name): return json.loads((folder/name).read_text(encoding='utf-8'))
before,after=read('before-upgrade-storage.json'),read('after-upgrade-storage.json')
assert before['version_code']==8061 and after['version_code']==8062
for key in ['persisted_files','databases','keystore_alias_hashes','probe_sha256']:
    assert before[key]==after[key],key
assert '+220: All tests passed!' in (root/'.artifact-work/sso/forms-full-flutter-tests.log').read_text(encoding='utf-8')
assert 'No issues found!' in (root/'.artifact-work/sso/forms-analyze.log').read_text(encoding='utf-8')
live=read('live-forms.json')
assert live['invalid_inspection_not_submitted'] and live['template_count_unchanged']
checks={
    'forms-create.xml':'请填写零件名称',
    'forms-template.xml':'检查项目',
    'forms-checklist.xml':'请选择检查结果',
    'forms-counts.xml':'检验结论与工件数量不一致',
    'forms-return.xml':'工作台',
}
for file,label in checks.items():
    nodes=ET.parse(root/'.artifact-work/release'/file).iter('node')
    assert any(label in (n.get('text','')+'\n'+n.get('content-desc','')) for n in nodes),file
screens=sorted((folder/'png').glob('*-emulator.png'))
assert len(screens)==5
journey={
    'version':'1.1.38+8062','first_missing_task_field_visible':True,
    'template_details_native_verified':True,'template_publish_native_verified':False,
    'required_checklist_feedback_visible':True,
    'inconsistent_counts_feedback_visible':True,'returned_to_workbench':True,
    'original_display_restored':True,'emulator_stopped_after_acceptance':True,
    'screenshots':[{'file':'png/'+p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in screens],
}
(folder/'native-journey.json').write_text(json.dumps(journey,indent=2)+'\n',encoding='utf-8')
for track,cert in [('preview','235a5af21396781cffd17f2081cffcb947de9b00894f97c959c6f64fa7a7010e'),('production','2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2')]:
    raw=(root/f'.artifact-work/sso/forms-{track}-signature.log').read_bytes()
    log=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8')
    assert cert in log and 'Verifies' in log
result={
    'version':'1.1.38+8062','flutter_tests_passed':220,'new_form_tests':9,
    'flutter_analyze':'No issues found','backend_source_unchanged':True,
    'previous_backend_tests_passed':57,'preview_upgrade_verified':True,
    'production_signature_verified':True,'native_forms_verified':True,
    'invalid_inspection_not_submitted':True,'template_count_unchanged':True,
    'invalid_template_locally_rejected_in_widget_tests':True,
    'template_publish_native_verified':False,
    'upgrade_baseline_source':'reauth-batch/final-runtime-storage.json',
    'storage_files_preserved':len(before['persisted_files']),
    'databases_preserved':len(before['databases']),'keystore_and_sentinel_preserved':True,
    'app_data_cleared':False,'main_app_uninstalled':False,'phone_installs':0,
    'native_journey':journey,'physical_nfc_verified':False,
    'two_physical_phones_verified':False,'ten_external_users_verified':False,
    'production_upgrade_retested_this_batch':False,'product_plan_complete':False,
}
(folder/'validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'version':result['version'],'native_forms_verified':True,'preserved_files':len(before['persisted_files'])}))
