import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
if(process.argv.includes('--inspect-only')) {
  console.log(JSON.stringify(rows.filter(row=>['REL-01','REL-03','QA-04'].includes(row[0]))));
  await fs.writeFile('.artifact-work/release-backlog-before.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A50:F57',scale:1,format:'png'})).arrayBuffer()));
  process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/release-batch/validation.json'),'utf8'));
if(!evidence.production_signature_verified || !evidence.preview_upgrade_verified) throw Error('Acceptance evidence missing');
const changes={
  'REL-01':['待验收','正式RSA3072签名与兼容升级签名分轨构建，缺失正式密钥时拒绝release，客户APK不包含验收工具。私钥有第二份本地备份，异地托管及发布流程待验收。'],
  'REL-03':['开发中','原8039→8058→8059安装存储校验9/12文件保留。图形兼容设置恢复原模拟器最终8059，登录和5条回执保留。独立正式同证书测试基线升级11文件/数据库/登录保留。真机仍待验收。'],
  'QA-04':['开发中','新增普通Android APK升级和二级页面模拟器截图，来源明确标注。双真机、物理卡/相机/触觉及10位外部用户仍待验收。'],
};
for(let i=0;i<rows.length;i++) {
  const change=changes[rows[i][0]]; if(!change) continue;
  const row=i+7;
  main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
  main.getRange(`H${row}:J${row}`).values=[['1.1.35+8059','acceptance/release-batch/; tool/build_signed_delivery.ps1',change[1]]];
  if(rows[i][0]==='REL-01') main.getRange(`G${row}`).values=[['正式签名、生产配置及覆盖升级可用。客户包无调试密钥/后台机密；内置演示凭证仅访问独立演示团队。']];
}
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:15},maxChars:1000})).ndjson);
await fs.writeFile('.artifact-work/release-backlog-after.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A50:J52',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
