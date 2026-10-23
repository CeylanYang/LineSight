import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'COL-03':['待验收','派工与任务更新通知已联调；版本化已读跨登录保留，旧回执不覆盖新状态。新增演示任务，原任务未改；最终APK原生流程验收待补。'],
 'UI-06':['待验收','通知支持本人待打印、打印中、待检及异常；防重复已读，局部刷新；中英文4状态组件PNG及真实云端联调通过。原生最终包验证待补。'],
 'UI-08':['开发中','通知三个入口统一按服务器任务编号进入详情；返回来源页面；切团队阻止旧结果。已读失败仅重读状态。270项测试通过，最终APK原生验证待补。'],
 'UI-09':['待联调','通知与我的待办可打开首页缓存外任务，受登录和团队范围约束；跨团队迟到结果不跳转。扫码真机及完整导航验收继续。'],
};
const render=async suffix=>fs.writeFile(`.artifact-work/notification-backlog-${suffix}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A33:J36',scale:1,format:'png'})).arrayBuffer()));
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/notification-batch/validation.json'),'utf8'));
if(!evidence.live_https_notification_flow_verified || evidence.flutter_full_tests_passed !== 270)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.41+8065','acceptance/notification-batch/; test/cloud_notifications_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
