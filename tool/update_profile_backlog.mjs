import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'QC-01':['待验收','配方中心补回本机配方/换型/系统入口，本机登录后访问；云端打印配置可查看来源与版本并选用创建任务，模板详情可按历史版本发起任务。原有模板复制/编辑/发布不变；工位关联与配置维护仍继续。实际HTTPS验证已有任务保留旧配置快照。'],
 'UI-08':['开发中','打印配置选择从原任务表单进入，确认后返回并保留已填内容；取消不修改设备，允许改为手工填写，所选配置随草稿恢复。本机页面整条导航栈随本机授权关闭；其他二级页继续审阅。'],
 'UI-11':['开发中','新增配置导航、配置列表/详情、已选配置任务表单、本机配置入口双语；10张360px组件PNG。任务表单按钮在窄屏等宽展示。最终APK原生逐屏验收继续。'],
 'QA-04':['开发中','新增10张中英文配置组件PNG；21项配置流程/本机授权与截图测试、374项Flutter全量、68项后端、静态检查和实际HTTPS通过。PNG为组件渲染，最终APK未完成原生逐屏验收。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/profile-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/profile-batch/validation.json'),'utf8'));
if(!evidence.live_https_profile_verified || evidence.flutter_full_tests_passed !== 374)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.46+8070','acceptance/profile-batch/; test/cloud_profile_workflow_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
