"""Append cloud UI vocabulary while retaining all existing message IDs."""
import json
from pathlib import Path

messages = {
    '返回工作台': 'Return to workbench',
    '搜索任务或设备': 'Search tasks or printers', '待打印': 'Queued', '打印中': 'Printing',
    '没有符合条件的任务。': 'No tasks match your filters.', '查看全部': 'View all',
    '零件名称': 'Part name', '请填写零件名称': 'Enter a part name', '打印设备': 'Printer',
    '请填写打印设备': 'Enter a printer', '工件数量': 'Piece quantity', '数量需要在1至999之间': 'Enter a quantity from 1 to 999',
    '创建任务': 'Create task', '创建时间': 'Created', '概览': 'Overview', '质检': 'Inspection', '历史': 'History',
    '开始打印': 'Start printing', '送检': 'Send for inspection', '登记检验': 'Record inspection',
    '处理异常': 'Resolve issue', '检验轮次': 'Round', '暂无异常': 'No issues', '当前任务没有异常记录。': 'This task has no issues.',
    '已处理': 'Resolved', '暂无事件': 'No events', '任务操作后可在这里查看历史。': 'Task activity appears here.',
    '任务状态更新': 'Task status updated', '检验合格': 'Inspection passed', '检验异常': 'Inspection failed',
    '创建异常': 'Issue created', '完成异常处置': 'Issue resolved', '任务操作': 'Task activity',
    '请填写处理或异常说明': 'Enter the resolution or describe the issue', '处理结果': 'Resolution', '检验备注': 'Inspection notes',
    '当前任务状态': 'Current task status', '返回并刷新任务': 'Return and refresh task', '确认提交': 'Submit',
    '任务已更新，请刷新后重试': 'This task has changed. Refresh it and try again.',
    '任务当前不能登记质检结果': 'This task is not ready for inspection.',
    '请先处理所有未完成异常': 'Resolve all open issues first.',
    '异常已处理或任务状态已更新，请刷新后重试': 'The issue or task has changed. Refresh it and try again.',
    '刷新': 'Refresh', '件': 'pieces', '异常': 'Issue', '待质检': 'Awaiting inspection',
    '异常处理中': 'Issues in progress', '已关闭': 'Closed',
    '登录后查看任务与检验记录': 'Sign in to view tasks and inspections',
    '暂无生产任务': 'No production tasks', '当前工作区还没有生产任务。': 'There are no production tasks in this workspace.',
    '暂无检验记录': 'No inspections', '完成检验后可在这里查看记录。': 'Completed inspections appear here.',
    '暂无检查模板': 'No checklists', '当前工作区还没有检查模板。': 'There are no checklists in this workspace.',
    '显示名称': 'Display name', '进入演示团队': 'Explore demo team',
    '退出登录？': 'Sign out?', '确认退出当前账号？': 'Sign out of this account?',
    '登录未完成，请重新登录': 'Sign-in was not completed. Please sign in again.',
    '登录未完成，请检查网络后重试': 'Sign-in was not completed. Check your connection and retry.',
    '无法连接服务，请检查网络后重试': 'Unable to connect. Check your connection and retry.',
    '连接超时，请重试': 'Connection timed out. Please retry.',
    '演示团队暂不可用，请稍后重试': 'The demo team is unavailable. Please try again later.',
    '登录已过期，请重新登录': 'Your session expired. Please sign in again.',
    '无法恢复登录，请检查网络后重试': 'Unable to restore your session. Check your connection and retry.',
    '请先登录': 'Please sign in first', '无法加载成员，请重试': 'Unable to load members. Please retry.',
}
path = Path('tool/l10n_source.json')
source = json.loads(path.read_text(encoding='utf-8'))
existing = set(source.values())
with Path('tool/en_translations.txt').open('a', encoding='utf-8') as out:
    for chinese, english in messages.items():
        if chinese in existing:
            continue
        key = str(max(map(int, source)) + 1)
        source[key] = chinese
        existing.add(chinese)
        out.write(f'{key}|{english}\n')
path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
