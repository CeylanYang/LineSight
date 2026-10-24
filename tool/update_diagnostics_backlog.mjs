import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={"REL-04": ["开发中", "同步诊断按401/403/服务故障提供登录、刷新权限或读取重试；本机草稿读取失败仍诊断云端。复制字段白名单不含错误正文、令牌和草稿。迟到结果与团队/角色隔离测试通过，完整故障日志审计继续。"], "UI-08": ["开发中", "同步诊断的恢复动作仅读取，不执行业务写入；401进入二级登录后可返回原诊断，403刷新权限；数量不可读显示—，切团队立即清空旧结果并忽略迟到请求。"], "UI-12": ["开发中", "使用说明更新为云端任务/检验/异常复检/报告与统一登录，移除没有云账户的旧说法；本机工位改为添加示例记录，生成中明确标记示例。原有存储记录保持不变。全App审阅继续。"], "UI-11": ["开发中", "新增健康诊断、服务故障与使用说明中英文组件PNG6张；旧登录图仅版本数字更新。帮助入口从我的直接进入、返回原账户页验证通过，索引306张；8074完整原生导航待补。"], "QA-04": ["开发中", "442项Flutter及静态检查通过；新增11项交互测试、6张双语组件PNG，索引306张。后端未改沿用87项后端与真实云端证据。用户暂无真机；8074原生、物理功能及外部用户验收继续。"]};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/diagnostics-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/diagnostics-batch/validation.json'),'utf8'));
if(evidence.flutter_full_tests_passed!==442 || evidence.new_component_png!==6 || !evidence.flutter_analyze_clean)throw Error('Navigation acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.50+8074','acceptance/diagnostics-batch/; test/diagnostics_recovery_test.dart',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
