"""Deliver the normal app entry and verified batch evidence; no private build inputs."""
import hashlib,json,shutil,zipfile
from pathlib import Path
root=Path(__file__).resolve().parents[1]
apk=root/'build/app/outputs/apk/release/app-release.apk'
with zipfile.ZipFile(apk) as z:
    assert 'lib/arm64-v8a/libapp.so' in z.namelist() and 'lib/x86_64/libapp.so' in z.namelist()
destination=Path('D:/ENT207/deliverables/LineSight-product-plan/cloud-preview-1.1.22')
destination.mkdir(parents=True,exist_ok=True)
name='LineSight-1.1.22-8032-cloud-preview.apk'
shutil.copy2(apk,destination/name)
for folder in ('sso','product-batch'):
    shutil.copytree(root/'docs/product/linesight/acceptance'/folder,destination/'evidence'/folder,dirs_exist_ok=True)
for suffix in ('xlsx','csv'):
    shutil.copy2(root/f'docs/product/linesight/LineSight_Development_Backlog.{suffix}',destination)
report={'version':'1.1.22+8032','entry':'lib/main.dart','apk':name,'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'bytes':apk.stat().st_size,
        'architectures':['arm64-v8a','x86_64'],'flutter_tests_passed':113,'django_tests_passed':32,
        'screenshots':len(list((destination/'evidence').rglob('*.png'))),
        'signing':'Existing debug-compatible certificate; formal release signing pending','product_plan_complete':False}
(destination/'build.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
(destination/'使用说明.md').write_text('''# LineSight 1.1.22 云端功能测试包

覆盖安装 APK。进入“登录”二级页面使用统一云账户，或选择“进入演示团队”。云端地址与隔离演示账号已内置。

本批新增：三套检查清单及版本发布、逐项三态检验、批次与数量校验、逐件SN、负责人指派、相机/相册入口、检验与整改前后证据、图片放大及边缘参考、检验快照与历史轮次、团队创建/加入/邀请/权限管理、待办提醒、质量趋势与报告、CSV/系统PDF打印、按身份及工作区隔离的任务草稿。

证据目录包含实际Android截图及云端API验证结果；开发台账保留全部需求与未完成事项。演示任务仅位于独立演示团队。

仍在开发：检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、正式签名、备份恢复演练。双真机与10名外部用户验收尚未实施。本包沿用现有证书以支持覆盖安装。
''',encoding='utf-8')
print(json.dumps({'destination':str(destination),'sha256':report['sha256'],'bytes':report['bytes'],'screenshots':report['screenshots']}))
