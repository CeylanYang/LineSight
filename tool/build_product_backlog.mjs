// Run a copy from .artifact-work with node_modules linked to runtime deps.
// Creates the missing master workbook once; never regenerates over human edits.
import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook, SpreadsheetFile} from '@oai/artifact-tool';

const root = process.cwd();
const dir = path.join(root, 'docs/product/linesight');
const out = path.join(dir, 'LineSight_Development_Backlog.xlsx');
try { await fs.access(out); throw new Error('Master workbook exists; edit it instead of regenerating.'); }
catch (e) { if (e.code !== 'ENOENT') throw e; }
const spec = await fs.readFile(path.join(dir, 'LINE_SIGHT_PRODUCT_PLAN.md'), 'utf8');
const pattern = /- \[ \] \*\*([A-Z]+-\d+)\*\* · (.+?)｜\*\*(P\d)\*\*｜状态：(.+?)｜展示价值 (\d)\/5｜复杂度 (\d)\/5\s+\*\*验收\*\*：(.+?)依赖：`([^`]+)`。/g;
const progress = {
  'SEC-01': ['开发中', 'test/local_import_authorization_test.dart', '已补本机角色与会话门禁；待Android入口与锁定留证'],
  'SEC-02': ['开发中', 'backend/collaboration/test_permissions.py', '后端401/403已验证；持久草稿与重认证流程待联调'],
  'SEC-05': ['开发中', 'backend/collaboration/test_permissions.py', '移除撤权、降级写权限已验证；新增报表接口后复核全部对象'],
  'COL-01': ['开发中', 'backend/collaboration/test_permissions.py', '成员改权/移除/离组已实现；待Android联调截图'],
  'QA-02': ['开发中', 'backend/collaboration/test_permissions.py', '已增401/403、旧令牌撤权与跨团队负例；状态机与并发待补'],
};
const rows = [...spec.matchAll(pattern)].map(m => {
  const [status, evidence, note] = progress[m[1]] ?? [m[4].trim(), '', ''];
  return [m[1], m[2], m[3], status, progress[m[1]] ? 'Codex' : '', m[8], m[7].trim(), '', evidence, note];
});
const allIds = [...spec.matchAll(/^- \[ \] \*\*([A-Z]+-\d+)\*\*/gm)].map(m=>m[1]);
if (rows.length !== allIds.length || new Set(rows.map(r=>r[0])).size !== rows.length) throw new Error('Requirement parse incomplete');
const wb = Workbook.create();
const sheet = wb.worksheets.add('开发台账');
sheet.showGridLines = false;
const end = rows.length + 6;
sheet.getRange(`A1:J${end}`).format.font = {name:'Arial',size:11,color:'#18243D'};
sheet.getRange(`A1:J${end}`).format.verticalAlignment = 'center';
sheet.getRange('A2').values = [['LineSight 开发台账']];
sheet.getRange('A2').format.font = {size:16,bold:true};
sheet.getRange('A3').values = [['条目总数']];
sheet.getRange('B3').formulas = [[`=COUNTA(A7:A${end})`]];
sheet.getRange('C3').values = [['已验收']];
sheet.getRange('D3').formulas = [[`=COUNTIFS(D7:D${end},"已验收")`]];
sheet.getRange('E3').values = [['开发中']];
sheet.getRange('F3').formulas = [[`=COUNTIFS(D7:D${end},"开发中")`]];
sheet.getRange('A4').values = [['来源：LINE_SIGHT_PRODUCT_PLAN.md v1.0（2026-10-23）；Excel为唯一状态主表。']];
sheet.getRange('A4').format.font = {size:10,color:'#526178'};
const headers = ['ID','功能','优先级','状态','负责人','依赖','验收标准','验收构建','证据路径','进展及未完成事项'];
sheet.getRange(`A6:J${end}`).values = [headers,...rows];
const table = sheet.tables.add(`A6:J${end}`,true,'DevelopmentBacklog');
table.showFilterButton = true;
sheet.getRange('A6:J6').format = {fill:'#246BFD',font:{bold:true,color:'#FFFFFF'},rowHeight:28,horizontalAlignment:'center'};
const widths = [13,42,10,13,12,28,85,18,62,76];
widths.forEach((width,i) => {sheet.getRangeByIndexes(0,i,end,1).format.columnWidth=width;});
sheet.getRange(`A7:J${end}`).format.rowHeight = 62;
for(const column of ['B','F','G','I','J']) sheet.getRange(`${column}7:${column}${end}`).format.wrapText = true;
sheet.getRange(`D7:D${end}`).dataValidation = {rule:{type:'list',values:['待核验','待开发','开发中','待联调','待验收','已验收','阻塞']}};
sheet.getRange(`D7:D${end}`).conditionalFormats.add('containsText',{text:'阻塞',format:{fill:'#FCE7E9',font:{color:'#B52F3F'}}});
sheet.getRange(`D7:D${end}`).conditionalFormats.add('containsText',{text:'开发中',format:{fill:'#FFF1CC',font:{color:'#825500'}}});
sheet.freezePanes.freezeRows(6);
sheet.freezePanes.freezeColumns(1);
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:'开发台账!A3:F3',tableMaxRows:1,tableMaxCols:6})).ndjson);
const png = await wb.render({sheetName:'开发台账',range:'A1:F12',scale:1.5,format:'png'});
await fs.mkdir(path.join(dir,'acceptance'),{recursive:true});
await fs.writeFile(path.join(dir,'acceptance/backlog-preview.png'),new Uint8Array(await png.arrayBuffer()));
await (await SpreadsheetFile.exportXlsx(wb)).save(out);
const quote = value => '"'+String(value).replaceAll('"','""')+'"';
await fs.writeFile(path.join(dir,'LineSight_Development_Backlog.csv'),'\uFEFF'+[headers,...rows].map(row=>row.map(quote).join(',')).join('\r\n')+'\r\n');
console.log(`${rows.length} requirements, 0 accepted; workbook created`);
