import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const master=wb.worksheets.getItem('开发台账');
const original=master.getRange('A7:J62').values;
for(let i=0;i<original.length;i++) {
  if(original[i][0]==='QA-04') master.getRange(`I${i+7}:J${i+7}`).values=[['acceptance/DEMO_INDEX.html; acceptance/vision-batch/','98张PNG可按来源检索：新增4张桌面组件图、5张生成追溯码、4张原图/算法输出；相机/扫码/NFC真机继续。']];
  if(original[i][0]==='SSO-03') master.getRange(`I${i+7}:J${i+7}`).values=[['acceptance/session-batch/; acceptance/sso/','临时普通账户真实PKCE修改密码后旧密码、访问及刷新令牌失效；退出指定会话及其他会话验证通过；SMTP仍未配置。']];
}
const rows=[
 ['VISION-01','轮廓算法替换','P0','待真机','Codex','QC-04','mean-shift平滑→Canny→骨架化；旧预览更新；对应原图处理','1.1.31+8050','backend/collaboration/vision.py; acceptance/vision-batch/','实际云端照片与本机12张素材处理通过；物理相机验证继续'],
 ['VISION-02','手机摄像头在线质检','P0','待真机','Codex','VISION-01','开启摄像头返回真实轮廓，后台释放；选用画面后归档','1.1.31+8050','lib/cloud_vision.dart; test/cloud_vision_test.dart','低分辨率单请求，实际HTTPS帧处理通过；组件状态验证，不是实机采集'],
 ['SCAN-01','工件及批次扫码','P0','待真机','Codex','DAT-02','二维码/条形码读取服务端批次、逐件状态；生成真实演示码','1.1.31+8050','lib/cloud_trace.dart; acceptance/vision-batch/live-api.json','演示批次已关闭、逐件合格，跨团队404和匿名401；实物扫码继续'],
 ['NFC-01','NFC卡片绑定及登录','P0','开发中','Codex','SSO-02','使用nfc_manager支持常见卡型，服务端认证及绑定管理','','pubspec.yaml','已加入官方插件依赖；NDEF、UID、ISO-DEP读取与服务端登录尚未交付'],
 ['NFC-02','NFC令牌刷新与撤销','P0','待开发','Codex','NFC-01','云端签发刷新并绑定卡片/设备，撤销后令牌失效','','','需接Keycloak认证扩展和服务端挑战验证，不以UID查表代替认证'],
];
const sheet=wb.worksheets.add('新增需求');sheet.showGridLines=false;
sheet.getRange('A1:J1').values=[['新增需求：摄像头、追溯与NFC','','','','','','','','','']];
sheet.getRange('A1').format.font={name:'Arial',size:16,bold:true,color:'#18243D'};
sheet.getRange('A3:J8').values=[master.getRange('A6:J6').values[0],...rows];
sheet.tables.add('A3:J8',true,'AddedRequirements');
sheet.getRange('A3:J3').format={fill:'#246BFD',font:{bold:true,color:'#FFFFFF'},rowHeight:28};
sheet.getRange('A4:J8').format.wrapText=true;sheet.getRange('A4:J8').format.rowHeight=80;
[15,32,10,13,12,20,65,20,65,75].forEach((width,i)=>sheet.getRangeByIndexes(0,i,8,1).format.columnWidth=width);
wb.recalculate();
await fs.writeFile('.artifact-work/vision-backlog.png',new Uint8Array(await (await wb.render({sheetName:'新增需求',range:'A3:F8',scale:1,format:'png'})).arrayBuffer()));
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:15},maxChars:1200})).ndjson);
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...master.getRange('A6:J62').values,...rows].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
