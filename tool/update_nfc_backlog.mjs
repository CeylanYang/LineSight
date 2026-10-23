import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const sheet=wb.worksheets.getItem('新增需求');
const rows=sheet.getRange('A4:J8').values;
for(let index=0;index<rows.length;index++){
 const row=index+4;
 if(rows[index][0]==='NFC-01'){
  sheet.getRange(`D${row}:E${row}`).values=[['待真机','Codex']];
  sheet.getRange(`H${row}:J${row}`).values=[['1.1.32+8052','lib/nfc_reader.dart; lib/screens/cloud_nfc.dart; acceptance/nfc-batch/','官方nfc_manager读取常见Android卡型；空白NDEF可初始化；设备密钥/账户绑定、我的卡片与二级刷卡登录已接云，实体卡/手机验证继续']];
 }
 if(rows[index][0]==='NFC-02'){
  sheet.getRange(`D${row}:E${row}`).values=[['待真机','Codex']];
  sheet.getRange(`H${row}:J${row}`).values=[['1.1.32+8052','backend/collaboration/nfc.py; deploy/nfc/; acceptance/nfc-batch/live-api.json','Keycloak SPI签发，60秒一次性签名挑战，刷新轮换、单会话退出、解绑后访问/刷新拒绝均真实HTTPS通过；生成卡片/密钥夹具，不是实体卡验收']];
 }
}
const master=wb.worksheets.getItem('开发台账');
const original=master.getRange('A7:J62').values;
for(let index=0;index<original.length;index++){
 const row=index+7;
 if(original[index][0]==='QA-04')master.getRange(`I${row}:J${row}`).values=[['acceptance/DEMO_INDEX.html; acceptance/nfc-batch/','106张PNG按实际来源、尺寸、哈希检索；本批8张桌面组件图。未启动模拟器，物理NFC、相机、扫码、双真机及外部用户验收继续。']];
 if(original[index][0]==='SSO-02')master.getRange(`I${row}:J${row}`).values=[['acceptance/sso/; acceptance/nfc-batch/; deploy/nfc/','原生PKCE不变，新增独立保密NFC客户端与官方Authenticator SPI；由Keycloak签发/刷新/退出，账户共用身份，服务端实时校验撤权；真实HTTPS链路通过。']];
}
wb.recalculate();
await fs.writeFile('.artifact-work/nfc-backlog.png',new Uint8Array(await(await wb.render({sheetName:'新增需求',range:'A3:F8',scale:1,format:'png'})).arrayBuffer()));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:15},maxChars:1200})).ndjson);
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...master.getRange('A6:J62').values,...sheet.getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
