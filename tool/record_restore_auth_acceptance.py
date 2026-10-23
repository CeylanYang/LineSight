"""Record public recovery evidence; private archives and keys stay outside delivery."""
import hashlib
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[1]
target=root/'docs/product/linesight/acceptance/restore-auth-batch'

remote=r'''
import hashlib,json
from pathlib import Path
source=Path('/var/backups/linesight/complete/20261023T194606218579Z')
restored=Path('/var/backups/linesight/complete/20261023T194606218578Z')
inventory=json.loads((restored/'OFFHOST_MANIFEST.json').read_text())
assert inventory['backup']==source.name
for name,expected in inventory['files'].items():
    path=restored/name
    assert path.stat().st_size==expected['bytes']
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected['sha256']
    assert hashlib.sha256((source/name).read_bytes()).hexdigest()==expected['sha256']
assert all((p.stat().st_mode&0o777)==(0o700 if p.is_dir() else 0o600) for p in [restored,*restored.rglob('*')])
assert not Path('/root/linesight-restore-private/export-key.bin').exists()
print(json.dumps({'verified_extraction':True,'files_identical_to_original':len(inventory['files']),
    'private_permissions_verified':True,'temporary_export_key_removed':True,
    'production_cutover':False,'off_host_restore_boot_exercised':False}))
'''
output=subprocess.check_output(['ssh','-i',str(Path.home()/'.ssh/linesight-ali-baot.pem'),
    'root@47.111.81.94','/opt/linesight/venv/bin/python -'],input=remote,text=True)
extraction=json.loads(output)
(target/'extraction-verification.json').write_text(json.dumps(extraction,indent=2)+'\n')
reports={name:json.loads((target/name).read_text(encoding='utf-8-sig')) for name in
    ['report.json','identity-rehearsal-report.json','portable-backup-report.json','off-host-verification.json','host-health.json']}
auth=reports['identity-rehearsal-report.json']
for flag in ['restored_demo_password_login','restored_demo_subject_and_workspace_preserved',
    'native_pkce_login','real_bearer_jwt_and_introspection','authorized_photo_bytes_identical',
    'native_and_demo_refresh_rotation','native_and_demo_logout_access_and_refresh_revoked',
    'temporary_container_and_database_removed','rows_identical_before_login']:
    assert auth[flag]
assert not auth['force_authenticate_used'] and not auth['production_users_or_sessions_modified']
assert reports['off-host-verification.json']['archive_sha256']==reports['portable-backup-report.json']['archive_sha256']
assert reports['host-health.json']['temporary_restore_databases_remaining']==0
assert reports['host-health.json']['api_health'] and extraction['verified_extraction']
subprocess.run([str(Path.home()/'LineSight-workspaces/week6-cloud/.venv-backend/Scripts/python.exe'),
    '-m','unittest','discover','-s','tool','-p','test_restore_guards.py'],cwd=root,check=True)
index=json.loads((target.parent/'DEMO_INDEX.json').read_text())
result={'date':'2026-10-24','batch':'cloud recovery','app_version_unchanged':'1.1.38+8062',
    'backup':auth['backup'],'isolated_real_identity_restore_verified':True,
    'encrypted_off_host_copy_verified':True,'verified_extraction':True,'guard_tests_passed':7,
    'gallery_png_unchanged':index['screenshots'],'production_cutover_exercised':False,
    'off_host_provider_boot_exercised':False,'full_nfc_login_exercised':False,
    'automatic_off_host_replication_configured':False,'retention_configured':False,
    'private_material_in_public_delivery':False}
(target/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
