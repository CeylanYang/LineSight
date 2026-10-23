import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const sheet=wb.worksheets.getItem('开发台账');
const rows=sheet.getRange('A7:J62').values;
const changes={
 'UI-04':['待真机','lib/cloud_lifecycle.dart; acceptance/closure-batch/','五阶段进度已接任务详情；异常处理/待复检独立分支，无异常关闭显示跳过；真实云端六状态夹具、窄屏中英文PNG与状态测试通过，触屏体验待真机'],
 'QC-07':['待真机','lib/screens/cloud_evidence_compare.dart; acceptance/closure-batch/','同一异常前后照片对比、各侧多图切换、放大/原图/边缘入口及缺图空态；切换身份/团队丢弃旧图与迟到结果。云端真实上传/绑定/闭环通过；PNG参考图添加演示划痕，不代表真实整改拍摄'],
 'COL-02':['开发中','lib/screens/cloud_sessions.dart; test/cloud_sessions_test.dart; acceptance/session-batch/; acceptance/closure-batch/','App会话列表/单会话退出/保留当前退出其他会话已接Keycloak官方API；真实PKCE改密、旧密码拒绝及访问/刷新撤销通过。共享演示不开放会话管理，SMTP找回与真机仍待完成'],
 'QA-04':['开发中','acceptance/DEMO_INDEX.html; acceptance/closure-batch/','118张PNG按来源、尺寸、哈希索引；新增10张桌面组件图及2张演示参考原图。未启动模拟器；物理卡/相机/扫码、双真机、外部用户和正式签名继续'],
};
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;sheet.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 sheet.getRange(`H${row}:J${row}`).values=[['1.1.33+8054',change[1],change[2]]];
}
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:15},maxChars:1000})).ndjson);
await fs.writeFile('.artifact-work/closure-backlog.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A29:F34',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...sheet.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
