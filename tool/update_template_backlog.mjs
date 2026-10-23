import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'QC-01':['待验收','模板支持复制、逐项必填/不适用设置及增删排序；新版本保留检查项ID和历史快照。列表默认最新、详情可查旧版本；发布回执与列表读取分开，真实HTTPS检验仍保留v1。原生功能验收继续。'],
 'SEC-04':['开发中','模板发布新增原子幂等回执、同键异内容409与基础版本核对；重放旧请求不新增版本，旧模板不改写。68项后端测试与实际HTTPS通过；其余写入契约继续核验。'],
 'UI-08':['开发中','模板提交后滚动显示成功回执或可恢复错误；列表读取失败不抹去已发布结果。重试仅GET，手动同内容再发布复用请求键。脏编辑返回确认、慢回执跨团队隐藏；全App审阅继续。'],
 'UI-11':['开发中','模板列表/详情/编辑/版本冲突/成功结果补齐中英文；320px大字与900px布局测试通过，新增14张双语组件PNG；最终APK原生逐屏验收继续。'],
 'UI-12':['开发中','模板提供直接可操作的版本核对提示，未知错误不原样展示；复制名称使用当前语言。检查项名称、必填及不适用选项以业务文案呈现，全App文案审阅继续。'],
 'QA-04':['开发中','演示索引新增模板列表、详情、编辑上下段、发布回执、冲突和统一登录组件PNG；实际HTTPS在新建隔离探针工作区验证，旧模板不变，临时身份删除。原生与组件素材分别标注。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/template-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/template-batch/validation.json'),'utf8'));
if(!evidence.live_https_template_verified || evidence.flutter_full_tests_passed !== 352)throw Error('Read state acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.45+8069','acceptance/template-batch/; test/cloud_template_workflow_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
