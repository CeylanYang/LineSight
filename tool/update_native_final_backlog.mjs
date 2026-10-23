import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'SEC-01':['待验收','云登录不能读取本机受保护数据；最终8071普通APK从配方中心进入本机区仍要求本机认证。组件已验证锁定隐藏预览及迟到回执；原生导出全角色仍待验收。'],
 'QC-01':['待验收','云配置创建/编辑/复制、默认模板版本绑定及修订冲突已联调。8071普通APK验证配置详情创建任务、换配置往返及模板版本回填；所有者编辑原生验收继续。'],
 'UI-11':['开发中','保留14张配置维护双语组件图；新增8071普通APK原生截图12张，覆盖二级登录、配方中心、配置选用、模板及本机门禁。其余页面原生双语验证继续。'],
 'QA-02':['已验收','78项后端回归通过；401/403、旧令牌撤权、越权ID与证据绑定、非法关闭/重开、重复提交和失效版本均有负例；真实HTTPS并发一成功一409。详见本批负例证据映射。'],
 'QA-04':['开发中','新增12张8071普通APK原生PNG，索引累计289张；399项Flutter、78项后端和静态检查沿用上一批。独立Android14冷启动成功，后续模拟器意外退出，未计为完整原生验收。'],
};
const render=async suffix=>{
 for(let i=0;i<rows.length;i++){
  if(!changes[rows[i][0]])continue;
  const row=i+7;
  await fs.writeFile(`.artifact-work/native-final-backlog-${suffix}-${rows[i][0]}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:`A${row}:J${row}`,scale:1,format:'png'})).arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/native-final-batch/validation.json'),'utf8'));
if(!evidence.cold_launch_passed || evidence.screenshots.length!==12 || evidence.full_native_acceptance_complete)throw Error('Unexpected native evidence');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.47+8071','acceptance/native-final-batch/; acceptance/profile-management-batch/',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
