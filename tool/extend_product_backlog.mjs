import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, Workbook, SpreadsheetFile} from '@oai/artifact-tool';

const dir = path.join(process.cwd(),'docs/product/linesight');
const target = path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb = await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const sheet = wb.worksheets.getItem('开发台账');
const table = sheet.tables.items.find(t=>t.name==='DevelopmentBacklog');
const current = sheet.getRange('A7:J57').values;
const additions = [
 ['SSO-01','内置服务端点与独立演示账号入口','P0','开发中','Codex','无','端点不向客户开放输入；演示账号密码预置且仅能访问独立演示团队','','lib/collaboration_api.dart; lib/screens/team_workspace.dart','已移除端点输入；待Keycloak演示账号初始化与入口接入'],
 ['SSO-02','开源Keycloak单点登录','P0','开发中','Codex','SSO-01','标准OIDC登录与签名/issuer/audience/时效校验；统一会话与登出','','decisions/0002-sso-and-customer-copy.md','已核对官方26.8.1发行版及服务器环境，待实际部署联调'],
 ['SSO-03','单点登录部署及演示身份初始化','P0','待开发','','SSO-02','初始化realm/client/user/密码与隔离团队，验证登录/过期/登出/权限并保留恢复步骤','','',''],
 ['SSO-04','普通用户与团队用户统一云端登录','P0','待开发','','SSO-02','统一身份；登录是App内二级路由；团队作为工作区；退出清除授权缓存，草稿按身份隔离','','decisions/0003-unified-cloud-account.md','后续业务页面采用该身份架构，停止扩展双登录入口'],
 ['UI-12','客户界面文案清理','P0','开发中','Codex','UI-11,SSO-04','无严谨性声明、元叙事、防御性叙事；业务提示直接可执行；中英文一致','','lib/screens/team_workspace.dart','已移除服务地址及部分说明文案，待全业务逐屏审阅'],
];
if(current.some(r=>r[0]==='SSO-01')) throw new Error('Extension already applied');
table.rows.add(null,additions);
const end=62;
sheet.getRange('A58:J62').format.font={name:'Arial',size:11,color:'#18243D'};
sheet.getRange('A58:J62').format.rowHeight=62;
sheet.getRange('A58:J62').format.verticalAlignment='center';
for(const col of ['B','F','G','I','J'])sheet.getRange(`${col}58:${col}62`).format.wrapText=true;
sheet.getRange('D58:D62').dataValidation={rule:{type:'list',values:['待核验','待开发','开发中','待联调','待验收','已验收','阻塞']}};
sheet.getRange('D58:D62').conditionalFormats.add('containsText',{text:'开发中',format:{fill:'#FFF1CC',font:{color:'#825500'}}});
sheet.getRange('B3').formulas=[[`=COUNTA(A7:A${end})`]];
sheet.getRange('D3').formulas=[[`=COUNTIFS(D7:D${end},"已验收")`]];
sheet.getRange('F3').formulas=[[`=COUNTIFS(D7:D${end},"开发中")`]];
for(const [index,row] of current.entries()) {
 if(row[0]==='SEC-05') sheet.getRange(`J${index+7}`).values=[['已验证移除撤权与降级写限制；原文要求的降级旧令牌读取撤权仍需团队授权版本实现']];
 if(row[0]==='COL-01') sheet.getRange(`I${index+7}:J${index+7}`).values=[['acceptance/foundation/','后端回归及Android改权/移除演示已留证；待统一身份下重验']];
 if(row[0]==='SEC-01') sheet.getRange(`I${index+7}:J${index+7}`).values=[['acceptance/foundation/; test/local_import_authorization_test.dart','已验证无本机身份不读数量/内容、锁定后撤销预览；新云端导航下兼容导入待复验']];
}
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'开发台账!A3:F3',tableMaxRows:1,tableMaxCols:6})).ndjson);
const preview=await wb.render({sheetName:'开发台账',range:'A58:F62',scale:1.5,format:'png'});
await fs.writeFile(path.join(dir,'acceptance/backlog-extension.png'),new Uint8Array(await preview.arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const rows=sheet.getRange(`A6:J${end}`).values;
const q=v=>'"'+String(v??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+rows.map(r=>r.map(q).join(',')).join('\r\n')+'\r\n');
