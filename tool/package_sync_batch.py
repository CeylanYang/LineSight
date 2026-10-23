"""Deliver the isolated, reproducible import and sync checkpoint."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root/'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22','1.1.26').replace('8032','8040')
source = source.replace("apk=root/'build/app/outputs/apk/release/app-release.apk'", "apk=root/'.artifact-work/sso/sync8040.apk'")
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch','query-batch','trace-batch','sync-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':126")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':36")
source = source.replace('本批新增：','本批新增：本机授权/预览/确认后云端导入、默认排除示例、重复导入去重、拍照中断结果恢复、WebP转PNG、真实分块上传百分比、云端回执、同步诊断和脱敏信息复制。此前已交付：任务二维码、统一登录与任务授权、检验日期筛选和趋势下钻。已有业务功能：')
source = source.replace('检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、正式签名、备份恢复演练。','全面角色/双语审计、正式签名、备份恢复演练、邮件找回。物理手机拍照与进程回收验收继续。')
exec(compile(source,str(root/'tool/package_product_batch.py'),'exec'))
report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
report['source_worktree_modified'] = bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip())
report['source_workspace'] = str(root)
report['evidence'] = 'evidence/sync-batch/validation.json'
(destination/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
