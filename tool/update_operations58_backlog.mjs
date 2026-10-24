import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const root=process.cwd(), dir=path.join(root,'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'SEC-05':['待验收','云端20261024','acceptance/roles56-batch/; acceptance/privacy58-batch/','真实PKCE四角色读取及创建权限通过。降权后旧令牌401，新只读令牌写入403；移除后404，最后管理员离组409。最终APK全角色及图片/导出撤权矩阵仍待复核。'],
 'COL-01':['待验收','云端20261024','acceptance/team-batch/; acceptance/roles56-batch/','成员管理及邀请表单已实现。真实PKCE验证四角色权限、降权/移除即时撤权及最后管理员约束；客户checkcheck团队未改动。全角色原生操作仍待验收。'],
 'COL-02':['待验收','云端20261024','acceptance/mail57-batch/; acceptance/session-batch/; acceptance/reauth-batch/','正式Keycloak经Postfix及163 SMTP465发信。真实邮件重置、新密码PKCE登录、旧密码拒绝及链接重放拒绝通过，注册仍关闭。修改/续期/撤会话沿用既有证据；成员需绑定本人邮箱，最终APK邮件往返待验收。'],
 'REL-01':['待验收','1.1.54+8078','acceptance/ota54-batch/; acceptance/release-batch/; OTA.md','正式与兼容签名8078 APK已交付，自托管flutter_patcher接入。模拟器后台下载、冷启动生效和签名回滚通过，登录保留。APK/OTA签名密钥独立异地托管及正式渠道运行仍待验收。'],
 'REL-02':['已验收','云端20261024','acceptance/restore-auth-batch/; acceptance/operations55-batch/; acceptance/mail57-batch/','业务/身份数据库及图片隔离恢复通过。自动加密异机复制和30天/周/月保留已运行；105文件及13项部署配置校验通过，含SMTP授权配置。第二台主机完整启动和生产切换未演练，解密钥独立异地托管待办。'],
 'REL-04':['待验收','云端20261024','acceptance/privacy58-batch/; acceptance/diagnostics-batch/','Django故障日志仅保留状态、路由模板、代码位置及请求编号；101项后端测试通过，线上敏感标记未入journal。Caddy官方过滤器502探针通过。App诊断复制白名单沿用既有证据，Android/插件异常日志仍待原生验收。'],
 'QA-02':['已验收','云端20261024','acceptance/privacy58-batch/; acceptance/roles56-batch/; acceptance/native-final-batch/','101项后端回归通过，原有越权/非法状态/幂等及并发负例保留。增加异常链与凭据日志负例，真实HTTPS四角色、降权旧令牌401、移除404及只读写入403通过。'],
 'QA-04':['待验收','1.1.54+8078','acceptance/ota54-batch/; acceptance/mail57-batch/; acceptance/privacy58-batch/','8078基线453项Flutter测试及静态检查通过；最新服务端101项通过。OTA升级/回滚/启动自动下载有6张模拟器PNG。邮件与故障日志线上验收已归档，最终全页面/全角色及物理设备验收仍待完成。'],
 'SSO-03':['待验收','云端20261024','acceptance/restore-auth-batch/; acceptance/mail57-batch/; deploy/sso/MAIL.md','身份恢复、登录/刷新/登出及团队隔离已通过。正式邮件重置全流程和注册关闭验证通过；12人checkcheck团队登录信息保留。恢复后完整NFC认证及最终APK登录回调仍待验收。'],
};
const render=async suffix=>{
 for(const [label,range] of [['mail','A40:J40'],['operations','A50:J53'],['roles','A11:J11']]){
  const blob=await wb.render({sheetName:'开发台账',range,scale:1,format:'png'});
  await fs.writeFile(path.join(root,`.artifact-work/operations58-${suffix}-${label}.png`),new Uint8Array(await blob.arrayBuffer()));
 }
};
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=async relative=>JSON.parse(await fs.readFile(path.join(dir,relative),'utf8'));
if(!(await evidence('acceptance/mail57-batch/production-reset.json')).external_reset_email_received)throw Error('Mail reset evidence missing');
if(!(await evidence('acceptance/privacy58-batch/live-logs.json')).journal_canary_absent)throw Error('Privacy evidence missing');
if((await evidence('acceptance/ota54-batch/validation.json')).flutter_tests!==453)throw Error('APK baseline missing');
await fs.copyFile(target,path.join(root,'.artifact-work/operations58-backlog-original.xlsx'));
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[[change[1],change[2],change[3]]];
}
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'开发台账!A3:F3',tableMaxRows:1,tableMaxCols:6})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
const output=path.join(root,'outputs/linesight-close-20261024');await fs.mkdir(output,{recursive:true});
await fs.copyFile(target,path.join(output,'LineSight_Development_Backlog.xlsx'));
console.log(JSON.stringify({updatedIds:Object.keys(changes),output}));
