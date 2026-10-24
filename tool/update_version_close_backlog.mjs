import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={"UI-08": ["待验收", "8074普通APK完成创建→指派→首检异常→交接→处置→复检关闭，返回工作台不再经过已提交表单。8075修复处理异常及分段自动定位，3项小屏测试通过；8075完整原生复测未做。"], "UI-11": ["待验收", "真实模拟器新增18张PNG及UI XML，索引324张。8074业务主链路通过；8075定位修复使用组件测试验证。用户要求本版收尾，其他页面与全角色原生验收留待后续。"], "QA-04": ["待验收", "版本收尾：445项Flutter、静态检查通过；后端未修改，沿用87项后端回归。8074原生业务链路与真实HTTPS读回一致，324张PNG已归档。用户当前无真机，物理功能、双真机、外部用户另列后续。"], "COL-03": ["待验收", "任务指派及异常交接已完成服务端和表单开发；8074普通APK实际改派、必填交接校验、交接到共享队列及处置复检通过，HTTPS读回两条指派历史。应用内通知沿用既有证据，全角色原生回归待验收。"]};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/version-close-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/section-focus-batch/validation.json'),'utf8'));
if(evidence.flutter_full_tests_passed!==445 || !evidence.flutter_analyze_clean)throw Error('Navigation acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.51+8075','acceptance/native50-batch/; acceptance/section-focus-batch/; test/task_section_navigation_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
