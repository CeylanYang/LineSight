import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';

const dir = path.join(process.cwd(), 'docs/product/linesight');
const target = path.join(dir, 'LineSight_Development_Backlog.xlsx');
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const sheet = wb.worksheets.getItem('开发台账');
const rows = sheet.getRange('A7:J62').values;
const changes = {
  'SSO-01': ['待验收', 'acceptance/sso/api-verification.json; acceptance/sso/png/02-unified-secondary-login.png', '内置端点与独立演示账号已实际接入；普通账户/演示团队相互隔离，越权API被拒绝'],
  'SSO-02': ['待验收', 'acceptance/sso/provider-verification.json; acceptance/sso/api-verification.json; deploy/sso/README.md', 'Keycloak 26.8.1已上线；真实PKCE登录、签名/issuer/audience校验、轮换刷新、退出即时撤权通过；Android使用AppAuth'],
  'SSO-03': ['待验收', 'acceptance/sso/api-deployment.json; acceptance/sso/legacy-password-verification.json; deploy/sso/README.md', 'realm/client/独立演示身份已初始化；5个旧账户保留原密码和团队关系；备份、回滚与原数据一致性已验证。SMTP重置邮件及身份库备份恢复演练仍待运维补齐'],
  'SSO-04': ['开发中', 'acceptance/sso/png/; test/cloud_account_test.dart; test/cloud_navigation_test.dart', '普通与团队统一云身份；二级登录、个人资料、工作区切换、安全令牌存储和退出已接入。新建/加入团队、完整成员管理及草稿身份隔离继续开发'],
  'UI-12': ['开发中', 'lib/screens/cloud_shell.dart; lib/screens/cloud_tasks.dart; acceptance/sso/png/', '新云端页面采用直接业务文案；成员页改用显示名称。后续页面与中英文仍需逐屏审阅'],
  'SEC-03': ['开发中', 'backend/collaboration/test_workflow.py; acceptance/sso/live-workflow-verification.json', '直接PATCH绕过异常关闭/复检已禁用；授权关闭需管理员+处置+依据，重复处理不能覆盖；真实云API已验证。模板/证据业务完整约束仍随后续模型补齐'],
  'SEC-04': ['开发中', 'backend/collaboration/test_workflow.py; acceptance/sso/live-workflow-verification.json; test/cloud_task_ui_test.dart', '任务状态、检验、异常处理采用事务版本CAS与幂等回执；真实并发一个成功一个409，前端保留输入并要求刷新。附件/其余写入契约继续完善'],
  'SEC-05': ['开发中', 'backend/collaboration/test_permissions.py; backend/collaboration/test_oidc.py', '旧token在角色变化后读取与写入均要求重新认证；移除成员失去对象访问权。统一云端角色切换真实Android回归仍待补齐'],
  'UI-02': ['开发中', 'lib/screens/cloud_tasks.dart; test/cloud_task_ui_test.dart', '已接真实云任务列表、搜索、状态筛选、新建及详情。负责人/批次筛选待数据字段补齐'],
  'UI-03': ['开发中', 'lib/screens/cloud_tasks.dart; backend/collaboration/workflow.py', '概览/质检/异常/历史二级分段、概要及推荐操作已接API；仍缺检查模板、证据对比与报告等后续契约'],
  'UI-04': ['开发中', 'lib/screens/cloud_tasks.dart; backend/collaboration/workflow.py', '五状态节点及异常分支已按后端渲染。完整横向进度视觉与真机留证继续'],
  'DAT-05': ['待开发', '', '数量/批次基础字段与合法性校验仍按原文待开发；当前只校验任务计划数1至999，尚未实现批次号与送检/合格/异常/报废数量守恒'],
  'DAT-06': ['开发中', 'backend/collaboration/workflow.py; acceptance/sso/live-workflow-verification.json', '任务创建、状态、检验、异常处置新增actor/time/object/version/details事件；工作区对象级隔离；旧历史映射与证据事件继续完善'],
};
for (let index = 0; index < rows.length; index++) {
  const id = rows[index][0], change = changes[id];
  if (!change) continue;
  const row = index + 7;
  if (rows[index][3] !== '已验收') sheet.getRange(`D${row}:E${row}`).values = [[change[0], 'Codex']];
  sheet.getRange(`I${row}:J${row}`).values = [[change[1], change[2]]];
}
wb.recalculate();
console.log((await wb.inspect({kind: 'table', range: '开发台账!A3:F3', tableMaxRows: 1, tableMaxCols: 6})).ndjson);
await (await SpreadsheetFile.exportXlsx(wb)).save(target);
const mirror = sheet.getRange('A6:J62').values;
const q = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
await fs.writeFile(path.join(dir, 'LineSight_Development_Backlog.csv'), '\uFEFF' + mirror.map(row => row.map(q).join(',')).join('\r\n') + '\r\n');
