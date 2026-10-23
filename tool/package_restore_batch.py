"""Package public operations evidence only; never include private cloud backups."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
destination = Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-operations-2026-10-23')
destination.mkdir(parents=True, exist_ok=True)
shutil.copytree(root / 'docs/product/linesight/acceptance/restore-batch', destination / 'evidence', dirs_exist_ok=True)
for suffix in ['xlsx', 'csv']:
    shutil.copy2(root / f'docs/product/linesight/LineSight_Development_Backlog.{suffix}', destination)
for name in ['RESTORE.md', 'linesight-cloud-backup.service', 'linesight-cloud-backup.timer']:
    shutil.copy2(root / 'deploy/sso' / name, destination)
scripts = destination / 'tool'; scripts.mkdir(exist_ok=True)
for name in ['rehearse_cloud_restore.py', 'test_cloud_restore.py', 'verify_backup_host.py']:
    shutil.copy2(root / 'tool' / name, scripts)
shutil.copy2(root / 'docs/product/linesight/acceptance/restore-batch/README.md', destination / '交付说明.md')
report = {
    'client_version': '1.1.27+8042', 'apk_rebuilt': False,
    'source_commit': subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
    'source_worktree_modified': bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()),
    'private_backup_data_included': False, 'emulator_started': False,
    'product_plan_complete': False,
    'files_sha256': {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in destination.rglob('*') if p.is_file() and p.name != 'build.json'},
}
(destination / 'build.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'destination':str(destination),'files':len(report['files_sha256']),'source_commit':report['source_commit']}))
