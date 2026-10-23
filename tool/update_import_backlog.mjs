import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'SEC-01':['待验收','云登录不能读取本机预览/数量；本机工程师授权后预览，锁定即隐藏预览及导入历史，迟到回执不显示。既有CSV拒绝未授权测试通过；最终APK原生验证待补。'],
 'DAT-04':['待验收','本机预览绑定本机会话、云身份/团队/角色；取消不上传，默认排除示例。真实HTTPS演示示例导入/重复去重/原始与最终结论保留通过；实际设备导入待验收。'],
 'UI-08':['开发中','导入成功与历史读取结果分开展示，失败重试只GET不重放导入；提交防重、切团队/本机锁定隐藏旧结果。18项新导入测试及8张中英文状态组件PNG通过。'],
 'UI-12':['开发中','本机导入隐藏未知异常与内部信息，业务失败提示双语；导入成功不被历史查询失败覆盖。全App逐屏文案审阅继续。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/import-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/import-batch/validation.json'),'utf8'));
if(!evidence.live_https_import_verified || evidence.flutter_full_tests_passed !== 288)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.42+8066','acceptance/import-batch/; test/cloud_import_ui_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
