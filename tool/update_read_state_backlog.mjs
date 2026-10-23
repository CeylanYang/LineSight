import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'UI-08':['开发中','工作台、模板、通知区分读取中、失败和有效空数据；整组成功才发布计数。记录统计只在独立查询成功后显示；无团队可创建或加入。最终普通APK中文断网截图留证；重试与英文组件测试通过，模拟器多次异常，最终包原生恢复及英文复验未完成。'],
 'UI-11':['开发中','新增工作区加载中、服务失败、有效空数据和未加入团队的中英文小屏组件PNG；最终普通APK中文断网留证；原生英文与最终重试复验待补。全业务逐屏与真机审阅继续。'],
 'UI-12':['开发中','读取失败不再显示零任务、无通知或已清空，使用既有双语恢复提示，隐藏未知原始错误。全App文案审阅继续。'],
 'QA-04':['开发中','新增读取状态中英文组件及普通APK中文断网PNG；8063覆盖8064保留文件、数据库与密钥别名证据。双真机与外部用户继续。'],
};
const render=async suffix=>fs.writeFile(`.artifact-work/read-state-backlog-${suffix}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A35:J35',scale:1,format:'png'})).arrayBuffer()));
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/read-state-batch/validation.json'),'utf8'));
if(!evidence.native_failure_hides_counts || !evidence.preview_upgrade_verified)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.40+8064','acceptance/read-state-batch/; test/cloud_workspace_read_ui_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
