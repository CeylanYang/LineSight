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
Object.assign(changes, {
  'DAT-01': ['开发中', 'lib/cloud_account.dart; lib/screens/cloud_shell.dart', '首页、任务、记录及统计均接同一云工作区；Android模拟器验证，双真机一致性待QA-01'],
  'DAT-02': ['待验收', 'backend/collaboration/product.py; backend/collaboration/tests.py; acceptance/product-batch/', '检验包含任务/轮次/人员/时间/数量/模板快照/图片关联，重新提交受版本与幂等约束'],
  'DAT-03': ['开发中', 'backend/collaboration/product.py; lib/screens/cloud_business.dart', '指标、CSV及PDF使用同一projection和工作区授权；任务报告按任务ID筛选，完整筛选UI继续'],
  'DAT-05': ['待验收', 'backend/collaboration/tests.py; lib/screens/cloud_tasks.dart', '批次号、送检/合格/异常/报废守恒和越界约束已上线，SN数量与结果一致性检查通过'],
  'QC-01': ['待验收', 'backend/collaboration/migrations/0005_starter_checklists.py; backend/collaboration/tests.py; lib/screens/cloud_business.dart', '三套四项内置清单；管理员发布不可变新版本；检验保留模板快照'],
  'QC-02': ['待验收', 'lib/screens/cloud_tasks.dart; backend/collaboration/tests.py', 'Pass/Fail/NA逐项录入，必填与不合格说明由服务端验证；真实检验保存快照与答案'],
  'QC-03': ['开发中', 'backend/collaboration/models.py; backend/collaboration/workflow.py; lib/screens/cloud_tasks.dart', '批次/逐件SN模式已接；SN团队内唯一，检验SN与工件数量守恒；Android逐件录入场景待补截图'],
  'QC-04': ['待联调', 'lib/screens/cloud_business.dart; backend/collaboration/api.py', '接入相机/相册、压缩、10MB客户端/16MP服务端校验，检验提交绑定已上传照片；相机真机验收待补'],
  'QC-05': ['待验收', 'backend/collaboration/workflow.py; backend/collaboration/product.py; acceptance/product-batch/', '复检新增轮次；原模板、结论、数量与照片关联不覆盖；检查项详情页面已接'],
  'QC-06': ['开发中', 'backend/collaboration/workflow.py; lib/screens/cloud_tasks.dart', '异常分类、严重度、任务负责人、创建人与处置说明均有持久数据；分类筛选入口继续'],
  'QC-07': ['待联调', 'backend/collaboration/api.py; lib/screens/cloud_tasks.dart; lib/screens/cloud_business.dart', '同一异常前后阶段照片分别上传与查看，支持放大/原图/边缘参考切换；批量弱网与真机照片留证继续'],
  'QC-08': ['开发中', 'backend/collaboration/workflow.py; backend/collaboration/test_workflow.py', '处理后进入复检；授权关闭服务端支持owner+处置+依据，移动端授权关闭入口继续'],
  'UI-03': ['待验收', 'lib/screens/cloud_tasks.dart; acceptance/product-batch/', '概览/质检/异常/历史四段、模板检查、照片与报告二级入口已接'],
  'UI-05': ['开发中', 'lib/screens/cloud_tasks.dart; backend/collaboration/workflow.py', '按真实事件时间排序展示操作者/动作/时间，头像与完整细节视觉继续'],
  'UI-06': ['开发中', 'backend/collaboration/product.py; lib/screens/cloud_shell.dart', '云端按指派/未指派任务生成待检、异常、复检提醒，可直达详情；已读状态继续'],
  'UI-07': ['待联调', 'lib/screens/cloud_business.dart', '图片缩放、原图/边缘切换已接；后台持久上传重试队列继续'],
  'UI-11': ['开发中', 'lib/l10n_catalog.dart; tool/add_cloud_translations.py; test/cloud_task_ui_test.dart', '新业务术语补齐双语，模板用户自定义内容保留原文；全部新页面窄屏回归继续'],
  'COL-01': ['待联调', 'lib/screens/cloud_business.dart; backend/collaboration/test_permissions.py', '统一云身份下新增创建/加入团队、邀请、改权/移除/离组入口，最后管理员和自操作约束由服务端执行'],
  'COL-03': ['开发中', 'lib/screens/cloud_tasks.dart; backend/collaboration/product.py', '任务支持团队成员指派，应用内待办跳转已接；持久已读通知继续'],
  'REP-01': ['待验收', 'backend/collaboration/product.py; backend/collaboration/tests.py', '首次合格数/首次送检数；最终放行数/已检任务计划数；空分母为null；旧记录未知数量不纳入数值比率'],
  'REP-02': ['开发中', 'backend/collaboration/product.py; lib/screens/cloud_business.dart', '7天工件数趋势与类别分布API已接；当前趋势条显示，分类图与下钻继续'],
  'REP-03': ['开发中', 'lib/screens/cloud_business.dart; assets/fonts/OFL-NotoSansSC.txt', '真实统计报告、任务筛选、系统PDF打印已接，开源中文字体内置；任务处置/证据明细报告继续'],
  'REP-04': ['开发中', 'backend/collaboration/product.py; lib/screens/cloud_business.dart; backend/collaboration/tests.py', 'CSV导出遵循同一团队授权和projection；PDF显示工作区与时间；完整来源/筛选条件页继续'],
  'OFF-01': ['开发中', 'lib/cloud_account.dart; lib/screens/cloud_tasks.dart', '任务草稿使用安全存储按云身份+工作区隔离并可恢复；检验草稿与照片离线队列继续'],
  'REL-03': ['开发中', 'acceptance/product-batch/deployment.json; tool/deploy_cloud_identity.py', '0004/0005已上线，备份后迁移并核对25张原表旧行、外键完整；Android覆盖安装留证继续'],
  'SSO-04': ['开发中', 'lib/screens/cloud_business.dart; lib/cloud_account.dart; acceptance/sso/', '普通和团队共享身份与二级登录；创建/加入/成员管理已接；任务草稿身份隔离，检验草稿继续'],
});
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
