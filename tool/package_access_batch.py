"""Deliver the isolated, reproducible import and sync checkpoint."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root/'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22','1.1.28').replace('8032','8044')
source = source.replace("apk=root/'build/app/outputs/apk/release/app-release.apk'", "apk=root/'.artifact-work/sso/access8044.apk'")
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch','query-batch','trace-batch','sync-batch','workbench-batch','restore-batch','access-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':137")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':37")
source = source.replace('本批新增：','本批新增：本机授权/预览/确认后云端导入、默认排除示例、重复导入去重、拍照中断结果恢复、WebP转PNG、真实分块上传百分比、云端回执、同步诊断和脱敏信息复制。此前已交付：任务二维码、统一登录与任务授权、检验日期筛选和趋势下钻。已有业务功能：')
source = source.replace('检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、正式签名、备份恢复演练。','全面角色/双语审计、正式签名、备份恢复演练、邮件找回。物理手机拍照与进程回收验收继续。')
exec(compile(source,str(root/'tool/package_product_batch.py'),'exec'))
report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
report['source_worktree_modified'] = bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip())
report['source_workspace'] = str(root)
report['evidence'] = 'evidence/access-batch/validation.json'
(destination/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')

(destination/'使用说明.md').write_text("""# LineSight 1.1.28

覆盖安装APK，在登录二级页面使用统一云账户或进入演示团队。端点已内置。

新增：账户/团队/角色切换后旧成员、图片和邀请码清理；原页面表单提交保护；姓名草稿按身份更新；130条英文目录补齐与320宽布局修复。此前任务、检验、整改、报告、导入、同步和追溯功能保留。

137项客户端测试通过，后端未改动；新增4张中英文PNG为360宽桌面组件渲染和固定演示夹具，文件名含desktop-render。没有执行实际密码修改或新增Android界面验收；SMTP、正式签名、升级及相机/双真机/外部用户测试继续。未启动模拟器，构建完成退出后台。
""",encoding='utf-8')
