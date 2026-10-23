import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'UI-07':['待验收','图片证据灯箱支持原图/轮廓、多图前后切换、双击放大与复位；切换重置视角，慢响应不覆盖当前图，损坏图可重载；小屏大字及云端真实下载测试通过，原生最终APK待验证。'],
 'QC-07':['待真机','整改前后对比保留各侧选择；详情照片图库限制在当前异常，返回保留来源。沿用云端已有演示前后照片及轮廓，未产生业务写入，实体拍摄验收继续。'],
 'UI-11':['开发中','图片灯箱补齐中英文阶段名称、切图/缩放复位与错误恢复；320px大字和900px平板布局测试通过，新增8张双语组件PNG，整App原生逐屏审阅继续。'],
 'UI-12':['开发中','图片页不再显示inspection/before/after等阶段代码；损坏图显示双语重载操作，不暴露内部异常。全App文案审阅继续。'],
 'QA-04':['开发中','新增云端演示图片及原图/轮廓/放大/失败中英文组件PNG，4次HTTPS读取与原任务不变留证；素材来源明确，不是物理相机或最终APK原生截图。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/evidence-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/evidence-batch/validation.json'),'utf8'));
if(!evidence.live_https_evidence_verified || evidence.flutter_full_tests_passed !== 307)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.43+8067','acceptance/evidence-batch/; test/cloud_evidence_viewer_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
