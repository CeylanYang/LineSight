import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'UI-03':['待验收','创建成功直接进入服务器回执对应任务详情，替换已提交表单；返回工作台/列表或原配置/模板详情。概览/质检/异常/历史及状态动作保留。新增返回路径测试，最终8072原生验收继续。'],
 'UI-08':['开发中','创建任务成功不等待列表刷新，详情读取失败仍显示已创建回执，刷新只读不重复创建；创建失败留表单。切团队或离开后的迟到结果不导航、不清草稿、不刷新新团队。其余页面反馈继续审阅。'],
 'OFF-01':['待验收','创建失败及迟到回执保留原草稿；成功后清理草稿，清理失败也进入成功详情，原请求键保留供服务器幂等重放。已有负责人/模板/SN切换即时保存和检验校验保留不变。'],
 'UI-11':['开发中','新增创建成功任务详情中英文360px组件PNG2张；原登录图仅更新版本数字。8071已有12张原生PNG，8072新增流程尚待原生与全页面双语验收。'],
 'QA-04':['开发中','新增8项创建导航交互测试及2张双语组件PNG，索引累计291张；409项Flutter及静态检查通过，后端未改沿用78项回归证据。8072完整原生、双真机和外部用户验收继续。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/create-navigation-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/create-navigation-batch/validation.json'),'utf8'));
if(evidence.flutter_full_tests_passed!==409 || evidence.new_component_png!==2 || !evidence.flutter_analyze_clean)throw Error('Navigation acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.48+8072','acceptance/create-navigation-batch/; test/cloud_create_navigation_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
