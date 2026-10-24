"""Create focused backlog and packaging scripts from established delivery contracts."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
changes={
 'UI-08':['待验收','8074普通APK完成创建→指派→首检异常→交接→处置→复检关闭，返回工作台不再经过已提交表单。8075修复处理异常及分段自动定位，3项小屏测试通过；8075完整原生复测未做。'],
 'UI-11':['待验收','真实模拟器新增18张PNG及UI XML，索引324张。8074业务主链路通过；8075定位修复使用组件测试验证。用户要求本版收尾，其他页面与全角色原生验收留待后续。'],
 'QA-04':['待验收','版本收尾：445项Flutter、静态检查通过；后端未修改，沿用87项后端回归。8074原生业务链路与真实HTTPS读回一致，324张PNG已归档。用户当前无真机，物理功能、双真机、外部用户另列后续。'],
 'COL-03':['待验收','任务指派及异常交接已完成服务端和表单开发；8074普通APK实际改派、必填交接校验、交接到共享队列及处置复检通过，HTTPS读回两条指派历史。应用内通知沿用既有证据，全角色原生回归待验收。'],
}
source=(root/'tool/update_diagnostics_backlog.mjs').read_text(encoding='utf-8')
start=source.index('const changes=');end=source.index(';\nconst render=',start)
source=source[:start]+'const changes='+json.dumps(changes,ensure_ascii=False)+source[end:]
source=source.replace('diagnostics-backlog','version-close-backlog').replace('diagnostics-batch/validation.json','section-focus-batch/validation.json')
source=source.replace('evidence.flutter_full_tests_passed!==442 || evidence.new_component_png!==6','evidence.flutter_full_tests_passed!==445')
source=source.replace('1.1.50+8074','1.1.51+8075').replace('acceptance/diagnostics-batch/; test/diagnostics_recovery_test.dart','acceptance/native50-batch/; acceptance/section-focus-batch/; test/task_section_navigation_test.dart')
(root/'tool/update_version_close_backlog.mjs').write_text(source,encoding='utf-8')
verify=(root/'tool/verify_diagnostics_backlog.py').read_text(encoding='utf-8')
verify=verify.replace('diagnostics-backlog-original','version-close-backlog-original').replace("{'UI-12', 'QA-04', 'UI-11', 'REL-04', 'UI-08'}",repr(set(changes))).replace('acceptance/diagnostics-batch/','acceptance/section-focus-batch/')
(root/'tool/verify_version_close_backlog.py').write_text(verify,encoding='utf-8')
package=(root/'tool/package_diagnostics_delivery.py').read_text(encoding='utf-8')
package=package.replace('diagnostics-batch','section-focus-batch').replace("validation['diagnostics_recovery_and_scope_verified']","validation['section_focus_verified']").replace('442','445').replace('306','324').replace('diagnostics-{track}','version-close-{track}').replace('1.1.50','1.1.51').replace('8074','8075')
(root/'tool/package_version_close_delivery.py').write_text(package,encoding='utf-8')
print('Prepared targeted closeout scripts')
