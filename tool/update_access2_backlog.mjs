import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob,SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'SEC-06':['待验收','backend/collaboration/test_object_scope.py; tool/verify_object_scope.py; acceptance/access2-batch/live-api.json','真实Bearer对象替换/写引用/导出参数/旧令牌撤权矩阵通过，非法写入无副作用；实际Keycloak PKCE跨团队12类读取404，匿名照片401，同团队错配图片404，导出范围隔离及原任务不变均通过'],
 'SEC-05':['开发中','backend/collaboration/test_permissions.py; backend/collaboration/test_object_scope.py; acceptance/access2-batch/','成员移除后旧Bearer读取任务/记录/图片/报告CSV等全部404；降权后重认证与只读禁写保留。真实Android角色变更回归继续'],
 'UI-10':['待真机','lib/store.dart; lib/ui.dart; lib/cloud_feedback.dart; test/cloud_haptics_test.dart; acceptance/access2-batch/','选择/成功/警告触觉已区分；成功只在服务端确认后且原身份仍有效时触发，等待/失败/身份变化不误报。全部页面路由尊重App及系统减少动态效果，卡片/图片返回值不丢；物理触觉待验证'],
 'UI-11':['开发中','lib/screens/cloud_tasks.dart; acceptance/access2-batch/png/; test/cloud_haptics_test.dart','本批任务按钮继承主题字体，检验照片按钮修复360宽英文溢出；成功/异常提示及路由均做双语组件验证。其余业务页面逐屏排版仍继续'],
 'REL-03':['开发中','acceptance/sync-batch/validation.json; acceptance/workbench-batch/; acceptance/access2-batch/','用户现已允许按需模拟器验证；本批未启动模拟器、未安装/卸载/清数据。普通APK覆盖升级、回执保留与登录恢复尚未执行，仍需验证'],
 'QA-04':['开发中','acceptance/DEMO_INDEX.html; acceptance/access2-batch/','124张PNG按来源、尺寸、哈希索引；本批6张桌面组件图，另有真实HTTPS授权矩阵与平台触觉调用记录。物理卡/相机/扫码、双真机、外部用户和正式签名继续'],
};
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['1.1.34+8056',change[1],change[2]]];
}
wb.recalculate();
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#NUM!',options:{useRegex:true,maxResults:15},maxChars:1000})).ndjson);
await fs.writeFile('.artifact-work/access2-backlog.png',new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A7:F12',scale:1,format:'png'})).arrayBuffer()));
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
