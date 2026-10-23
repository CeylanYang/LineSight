import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
  'OFF-03':['待验收','冲突对比编辑时与最新版本、状态及检验轮次。查看最新任务后返回保留草稿。更换检查模板需重新核对，SN按最新任务同步。云端并发关闭任务后Android旧表单提交409，未重复写入。'],
  'UI-11':['开发中','360宽及1.25倍文字中英冲突对比通过渲染检查。补齐Status翻译。Android账户卡片整块点击进入账户信息，返回保留我的页。全流程逐屏排版及真机仍待验收。'],
  'UI-12':['开发中','本批将检验提交页底部说明改为任务历史与补充照片的业务说明。尚不代表全App文案逐页验收。'],
  'SSO-04':['开发中','账户卡片整块进入账户二级页，返回保留我的页。演示会话通过标准端点刷新，撤销/失效时返回登录。统一登录及NFC沿用既有批次证据，物理卡仍待验收。'],
  'QA-04':['开发中','新增冲突处理、最新详情返回及账户二级页PNG，区分组件渲染和Android模拟器。199项Flutter测试通过。双真机、物理卡/相机/触觉及10位外部用户仍待验收。'],
};
if(process.argv.includes('--inspect-only')) {
  console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
  await fs.writeFile('.artifact-work/conflict-backlog-before.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A49:J49',scale:1,format:'png'})).arrayBuffer()));
  process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/conflict-batch/validation.json'),'utf8'));
if(!evidence.preview_upgrade_verified || !evidence.live_conflict_verified) throw Error('Acceptance evidence missing');
for(let i=0;i<rows.length;i++) {
  const change=changes[rows[i][0]]; if(!change) continue;
  const row=i+7;
  main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
  main.getRange(`H${row}:J${row}`).values=[['1.1.36+8060','acceptance/conflict-batch/; test/cloud_conflict_review_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await fs.writeFile('.artifact-work/conflict-backlog-after.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A49:J49',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
