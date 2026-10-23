import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
  'SEC-02':['待验收','会话失效后同账户二级登录恢复原表单、草稿和请求键。重新核验原工作区、权限与最新任务，变化时转冲突对比。换账户/降权阻止继续。普通APK定点撤销本次演示会话并完成恢复，未自动提交。'],
  'UI-08':['待验收','401只读恢复在成功登录后重新读取。取消/加载失败留在原流程。草稿恢复有加载、权限及网络重试，提交后返回的父任务详情重新读取。'],
  'UI-11':['开发中','统一登录页采用个人与团队共用表述并提供中英PNG。恢复流程覆盖同账户、换账户、只读、取消、网络失败和任务变化。其余页面及真机排版仍待验收。'],
  'UI-12':['开发中','登录页移除仅团队账号的表述，改为登录工作区、使用账号继续和业务说明。保留独立演示团队入口。全App逐屏文案审阅继续。'],
  'SSO-04':['开发中','普通与团队共用二级登录。重新登录后恢复同账户原工作区与草稿，父任务页返回刷新。不同账户不显示旧草稿。NFC实际卡片仍待验收。'],
  'COL-02':['开发中','本批实际撤销新创建的Android演示会话，旧令牌提交被拒，重新登录后恢复草稿并手动完成一条检验。云端密码修改沿用既有证据，SMTP找回仍未配置。'],
  'QA-04':['开发中','新增统一登录和失效会话恢复的普通Android APK截图，更新索引。211项Flutter测试通过。双真机、物理卡/摄像头/触觉和10位外部用户仍待验收。'],
};
if(process.argv.includes('--inspect-only')) {
  console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
  await fs.writeFile('.artifact-work/reauth-backlog-before.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A8:J8',scale:1,format:'png'})).arrayBuffer()));
  process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/reauth-batch/validation.json'),'utf8'));
if(!evidence.preview_upgrade_verified || !evidence.live_reauthentication_verified) throw Error('Acceptance evidence missing');
for(let i=0;i<rows.length;i++) {
  const change=changes[rows[i][0]]; if(!change) continue;
  const row=i+7;
  main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
  main.getRange(`H${row}:J${row}`).values=[['1.1.37+8061','acceptance/reauth-batch/; test/cloud_reauthentication_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await fs.writeFile('.artifact-work/reauth-backlog-after.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A8:J8',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
