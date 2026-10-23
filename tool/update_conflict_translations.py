"""Append the conflict review copy to the existing translation catalog."""
import json
from pathlib import Path

source_path=Path('tool/l10n_source.json')
translation_path=Path('tool/en_translations.txt')
source=json.loads(source_path.read_text(encoding='utf-8'))
additions={
    '状态':'Status',
    '编辑时':'When editing',
    '任务更新后':'Updated task',
    '任务名称':'Task name',
    '工件数量':'Part quantity',
    '打印设备':'Printer',
    '检查模板':'Inspection checklist',
    '更新时间':'Updated at',
    '查看最新任务':'View latest task',
    '检查模板已更新，请重新逐项核对。':'The checklist has changed. Review each item again.',
    '提交后可在任务历史中查看结果并补充照片。':'After submitting, view the result and add photos from task history.',
    '未选择':'Not selected',
}
lines=translation_path.read_text(encoding='utf-8').splitlines()
for text,english in additions.items():
    if text in source.values(): continue
    key=str(max(map(int,source))+1)
    source[key]=text
    lines.append(f'{key}|{english}')
source_path.write_text(json.dumps(source,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
translation_path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
