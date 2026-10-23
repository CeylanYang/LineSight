import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'UI-08':['开发中','返回工作台切换标签并清空上层路由；普通返回保留来源。追溯接统一恢复操作，表单缺项定位保留。另发现冷启动读取失败时工作台计数显示0，待修复后验收。'],
 'UI-09':['待联调','追溯链接失败保留HTTP状态，按登录、刷新权限或返回工作台恢复，不显示原始异常。真实无效任务链接404在中英文普通APK留证；实体扫码继续待验收。'],
 'UI-11':['开发中','普通APK中英文追溯失败与返回工作台页面已留证，未新增硬编码提示。小屏登录及全量240项Flutter测试通过；全业务逐屏与真机审阅继续。'],
 'UI-12':['开发中','追溯错误页使用已翻译业务提示与可执行恢复操作，隐藏未知原始错误。统一登录文案沿用8061；全App文案审阅继续。'],
 'QA-04':['开发中','新增普通APK二级账户页、返回来源、系统返回及中英文追溯恢复PNG；8062覆盖8063保持12文件/1数据库/密钥别名一致，原会话未恢复并重新登录。双真机与外部用户继续。'],
};
const render=async suffix=>fs.writeFile(`.artifact-work/navigation-backlog-${suffix}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A35:J35',scale:1,format:'png'})).arrayBuffer()));
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/navigation-batch/validation.json'),'utf8'));
if(!evidence.native_secondary_back_preserves_profile || !evidence.native_unavailable_trace_explicit_workbench_zh_en || !evidence.preview_upgrade_verified)throw Error('Navigation acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.39+8063','acceptance/navigation-batch/; test/cloud_navigation_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
