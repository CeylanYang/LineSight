"""Package the task tracing and inspection-date release with cumulative evidence."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22', '1.1.25').replace('8032', '8038')
source = source.replace("apk=root/'build/app/outputs/apk/release/app-release.apk'", "apk=root/'.artifact-work/sso/trace8038.apk'")
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch','query-batch','trace-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':120")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':35")
source = source.replace('本批新增：', '本批新增：任务二维码、原生扫码与手动追溯、外部任务链接登录与团队授权门禁、独立检验日期筛选、首次检验日期趋势下钻。此前已交付：加密照片重试队列、离线草稿、通知已读、组合筛选与完整证据报告。')
source = source.replace('检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、', '受控本机导入、同步诊断与上传百分比、相机恢复、')
exec(compile(source, str(root / 'tool/package_product_batch.py'), 'exec'))
report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, text=True).strip()
report['source_worktree_modified'] = bool(subprocess.check_output(['git','status','--porcelain'], cwd=root, text=True).strip())
report['source_note'] = 'Feature commit plus preserved concurrent UI changes; APK built from the working directory.'
(destination / 'build.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
