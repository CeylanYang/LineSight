import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'COL-01':['待验收','邀请先选择权限再生成，连续生成保留所选权限；云端is_self识别本人并允许管理其他管理员。改权/移除确认绑定原成员与团队，取消或换团队不提交，离组成功才返回。21项新测试、60项后端测试及HTTPS身份读取通过，原生角色联调待验收。'],
 'COL-04':['待验收','本人菜单由服务端认证标识控制，不比较显示名或OIDC映射ID。只读角色隐藏邀请/管理；换团队清空列表和邀请码，弹窗期间换账户不创建/加入团队。双语小屏大字测试通过，真实Android全角色回归继续。'],
 'SEC-05':['开发中','保留移除后旧Bearer访问任务/图片/导出404与降权只读约束；本批服务端增加认证本人标识，前端改权/移除按原团队提交。60项后端回归通过，真实Android即时撤权验收继续。'],
 'UI-08':['开发中','团队列表未读取或读取失败时隐藏人数，避免显示虚假0人；失败使用统一操作提示，重试只GET，不重复邀请/改权/移除。离组失败停留，成功返回来源页；全App反馈审阅继续。'],
 'UI-12':['开发中','成员列表显示姓名与业务角色，隐藏OIDC内部用户名；邀请提示与实际操作一致，未知服务端错误不直接展示。新增中英文组件PNG，全App文案审阅继续。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/team-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/team-batch/validation.json'),'utf8'));
if(!evidence.live_https_team_verified || evidence.flutter_full_tests_passed !== 328)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.44+8068','acceptance/team-batch/; test/cloud_team_workflow_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
