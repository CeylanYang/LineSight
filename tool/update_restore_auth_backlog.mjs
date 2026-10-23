import fs from 'node:fs/promises';
import path from 'node:path';
import {FileBlob, SpreadsheetFile} from '@oai/artifact-tool';
const dir=path.join(process.cwd(),'docs/product/linesight');
const target=path.join(dir,'LineSight_Development_Backlog.xlsx');
const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(target));
const main=wb.worksheets.getItem('开发台账');
const rows=main.getRange('A7:J62').values;
const changes={
 'REL-02':['已验收','31张业务表、101张身份表及28张图片恢复一致；真实登录、刷新、登出和权限通过。104文件加密取回并隔离解包核验，回滚步骤已写。自动异机复制/保留周期及生产切换未演练。'],
 'SSO-03':['待验收','恢复后的原演示账号和普通账号真实登录、刷新、登出及团队隔离通过，NFC插件恢复可加载。SMTP找回邮件及完整NFC恢复登录仍待验收。'],
};
const render=async suffix=>fs.writeFile(`.artifact-work/restore-auth-backlog-${suffix}.png`,new Uint8Array(await(await wb.render({sheetName:'开发台账',range:'A51:J51',scale:1,format:'png'})).arrayBuffer()));
if(process.argv.includes('--inspect-only')){
 console.log(JSON.stringify(rows.filter(row=>changes[row[0]])));
 await render('before');process.exit(0);
}
const evidence=JSON.parse(await fs.readFile(path.join(dir,'acceptance/restore-auth-batch/validation.json'),'utf8'));
if(!evidence.isolated_real_identity_restore_verified || !evidence.encrypted_off_host_copy_verified || !evidence.verified_extraction)throw Error('Recovery acceptance missing');
for(let i=0;i<rows.length;i++){
 const change=changes[rows[i][0]];if(!change)continue;
 const row=i+7;
 main.getRange(`D${row}:E${row}`).values=[[change[0],'Codex']];
 main.getRange(`H${row}:J${row}`).values=[['云端20261024','acceptance/restore-auth-batch/; deploy/sso/RESTORE.md',change[1]]];
}
wb.recalculate();
console.log(JSON.stringify(main.getRange('A7:J62').values.filter(row=>changes[row[0]])));
console.log((await wb.inspect({kind:'table',range:'开发台账!A3:F3',tableMaxRows:1,tableMaxCols:6})).ndjson);
console.log((await wb.inspect({kind:'match',searchTerm:'#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A|#NUM!|#NULL!|#SPILL!|#CALC!',options:{useRegex:true,maxResults:30},maxChars:1500})).ndjson);
await render('after');
await(await SpreadsheetFile.exportXlsx(wb)).save(target);
const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[...main.getRange('A6:J62').values,...wb.worksheets.getItem('新增需求').getRange('A4:J8').values].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
