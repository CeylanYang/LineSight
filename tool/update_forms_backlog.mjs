import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
  'DAT-05':['待验收','新建任务在本机校验SN数量、唯一性和长度，错误直接定位输入区；后台仍执行跨任务SN唯一性校验。负责人支持改回未指派，选择后立即保存草稿。'],
  'QC-01':['待验收','模板发布先校验名称、3至6项及单项120字符限制，定位首个缺项；发布期间输入禁用，旧工作区回调不能写入其他团队。历史模板快照沿用既有实现。'],
  'QC-02':['待验收','检验提交前逐项检查必填结论和不合格问题说明，缺项显示在对应检查项下方并滚动定位；无效表单不发出业务写入，原草稿保留。'],
  'QC-03':['待验收','检验本机校验非负整数、计划数量上限及结论与数量一致；SN逐件结论必填。服务端数量门禁保留。'],
  'UI-08':['待验收','新建任务、检验/异常处理、模板发布统一定位首个错误；缺项提示贴近字段，减少小屏上下查找。登录恢复和错误卡保留既有验证。'],
  'UI-11':['开发中','补齐表单数量/处置分组和校验提示的中英翻译，360宽中英文检查清单PNG已留存；全App及真机逐屏审阅继续。'],
  'OFF-01':['待验收','模板、负责人和SN模式切换后立即保存新建任务草稿；未指派可恢复。检验本机校验失败保留清单、数量和备注，登录恢复沿用8061。'],
  'QA-04':['开发中','新增表单缺项与数量校验的普通Android APK截图及中英文组件PNG，更新素材索引。220项Flutter测试通过；双真机及10位外部用户待验收。'],
};
if(process.argv.includes('--inspect-only')) {
  console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
  await fs.writeFile('.artifact-work/forms-backlog-before.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A19:J19',scale:1,format:'png'})).arrayBuffer()));
  process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/forms-batch/validation.json'),'utf8'));
if(!evidence.native_forms_verified || !evidence.preview_upgrade_verified) throw Error('Acceptance evidence missing');
for(let i=0;i<rows.length;i++) {
  const change=changes[rows[i][0]]; if(!change) continue;
  const row=i+7;
  main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
  main.getRange(`H${row}:J${row}`).values=[['1.1.38+8062','acceptance/forms-batch/; test/cloud_form_validation_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await fs.writeFile('.artifact-work/forms-backlog-after.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A19:J19',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
