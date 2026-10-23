import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'QC-01':['待验收','云端打印配置支持创建/编辑/复制及默认模板版本绑定；任务携带配置修订，失效修订409。实际HTTPS验证旧任务保留原配置与检查模板、新任务采用新配置。原有本机工位关联补图；原生逐屏验收继续。'],
 'SEC-04':['开发中','配置维护新增原子幂等回执、同键异内容/异账号拒绝及修订冲突；实测并发编辑一个成功一个409。迁移新增默认模板和修订字段，31张表既有行核对通过。其余写入契约继续审阅。'],
 'UI-08':['开发中','配置保存后直接更新详情与列表，延迟旧列表响应不擦掉成功回执；脏编辑返回确认，冲突可显式保留编辑后手动保存，跨团队迟到结果隐藏。其余二级页面反馈继续审阅。'],
 'UI-11':['开发中','新增配置创建/编辑/复制、默认检查模板、冲突/保存结果与本机换型双语PNG14张。组件图字体已核对，360px页面无溢出；最终APK原生逐屏验收继续。'],
 'QA-04':['开发中','新增14张配置维护/模板关联/本机换型组件PNG，索引累计277张。399项Flutter、78项后端与静态检查通过；隔离工作区真实HTTPS并发和快照验证通过。组件素材与原生验收分别标注。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/profile-management-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/profile-management-batch/validation.json'),'utf8'));
if(!evidence.live_https_profile_management_verified || evidence.flutter_full_tests_passed !== 399)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.47+8071','acceptance/profile-management-batch/; test/cloud_profile_management_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
