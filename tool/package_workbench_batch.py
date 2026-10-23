"""Deliver the isolated, reproducible import and sync checkpoint."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root/'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22','1.1.27').replace('8032','8042')
source = source.replace("apk=root/'build/app/outputs/apk/release/app-release.apk'", "apk=root/'.artifact-work/sso/workbench8042.apk'")
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch','query-batch','trace-batch','sync-batch','workbench-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':129")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':37")
source = source.replace('本批新增：','本批新增：本机授权/预览/确认后云端导入、默认排除示例、重复导入去重、拍照中断结果恢复、WebP转PNG、真实分块上传百分比、云端回执、同步诊断和脱敏信息复制。此前已交付：任务二维码、统一登录与任务授权、检验日期筛选和趋势下钻。已有业务功能：')
source = source.replace('检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、正式签名、备份恢复演练。','全面角色/双语审计、正式签名、备份恢复演练、邮件找回。物理手机拍照与进程回收验收继续。')
exec(compile(source,str(root/'tool/package_product_batch.py'),'exec'))
report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
report['source_worktree_modified'] = bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip())
report['source_workspace'] = str(root)
report['evidence'] = 'evidence/workbench-batch/validation.json'
(destination/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')

(destination/'使用说明.md').write_text("""# LineSight 1.1.27

覆盖安装APK，在登录二级页面使用统一云账户或进入演示团队，端点已内置。

新增：今日待检/今日关闭按本地日历进度更新时间统计且点击同范围下钻、我的待办三分类、7日首次检验趋势、正确未读数和未知角色写入入口关闭。此前的导入、照片恢复/上传、质量报告与任务追溯均保留。

本批新增4张中英文360宽PNG来自实际Flutter组件桌面渲染和固定演示夹具，文件名含desktop-render；此前截图证据保留原来源。129客户端与37后端测试通过，云端范围一致性验证通过。未启动模拟器；本批Android页面和覆盖升级、相机/系统回收仍待真机。正式签名与全部产品计划继续开发。
""",encoding='utf-8')
