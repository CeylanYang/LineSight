import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={"COL-03": ["待验收", "任务详情新增改派表单；当前团队有效负责人可接手，未分配进入共享队列；异常交接同步未完成异常并通知接手人。真实HTTPS通知/已读/改派及修复复检通过，最终原生待补。"], "QC-06": ["待验收", "异常交接说明必填；全部未完成异常随任务改派，原检验与已解决异常保持不变。历史展示前后负责人及说明；9项后端新增测试和真实云端验证通过。"], "UI-03": ["待验收", "任务详情可进入更改负责人二级表单；提交成功回到原任务并直接显示回执。原创建成功进入详情及返回来源逻辑保留；8073完整原生待补。"], "UI-08": ["开发中", "改派保存成功直接返回，未保存返回确认、提交中防连点；失败保留选择与说明，重试仅读成员；冲突须核对最新任务后手动保存。其余页面持续审阅。"], "UI-11": ["开发中", "新增改派/异常交接/版本冲突/历史中英文组件PNG8张；六张原组件图仅负责人入口或版本数字变化。累计300张，8073模拟器升级/冷启动通过，后续进程退出，完整导航与双语验收继续。"], "SEC-04": ["开发中", "改派使用事务、版本及幂等回执；同键异内容/异账号拒绝，旧版本409；跨团队、只读与关闭任务拒绝。真实HTTPS并发一成功一冲突，既有数据部署核对保留。"], "QA-04": ["开发中", "425项Flutter与87项后端测试及静态检查通过；新增16项Flutter和9项后端用例，8张双语组件PNG，索引300张；真实HTTPS交接闭环通过，双真机及最终原生验收继续。"]};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/assignment-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/assignment-batch/validation.json'),'utf8'));
if(evidence.flutter_full_tests_passed!==425 || evidence.new_component_png!==8 || !evidence.flutter_analyze_clean)throw Error('Navigation acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.49+8073','acceptance/assignment-batch/; test/cloud_assignment_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
