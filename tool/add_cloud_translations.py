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
messages.update({
'复制追溯号':'Copy trace ID', '搜索零件、批次或检验人':'Search parts, batches or inspectors', '检查模板':'Checklists', '检查项':'checks', '必填':'Required', '选填':'Optional', '发布检查模板':'Publish checklist', '发布新版本':'Publish new version', '模板名称':'Checklist name', '检查项，每行一项（3至6项）':'Checks, one per line (3–6)', '发布':'Publish',
'团队与权限':'Team and permissions', '创建团队':'Create team', '加入团队':'Join team', '输入邀请码':'Enter invitation code', '邀请成员权限':'Invitation role', '生成邀请码':'Create invitation', '复制邀请码':'Copy invitation', '更新成员权限':'Update member role', '移除成员':'Remove member', '离开团队':'Leave team',
'批次号':'Batch', '负责人':'Assignee', '逐件SN追踪':'Track each serial number', 'SN，每行一个':'Serial numbers, one per line', '报废':'Scrap', '不适用':'N/A', '查看证据':'View photo', '图片证据':'Photo evidence', '原图':'Original', '边缘参考':'Edge reference', '拍照':'Take photo', '从相册选择':'Choose from gallery',
'质量洞察与报告':'Quality insights and reports', '首次通过率':'First pass rate', '最终放行率':'Final release rate', '首次送检工件':'First inspected pieces', '最终放行工件':'Released pieces', '异常工件':'Failed pieces', '报废工件':'Scrapped pieces', '最近7天':'Last 7 days', '打印质量报告':'Print quality report', '质量报告':'Quality report', '导出CSV':'Export CSV',
'待办提醒':'To do', '待复检':'Awaiting reinspection', '待处理':'Pending', '处置前照片':'Before photos', '处置后照片':'After photos', '合格数量':'Passed pieces', '异常数量':'Failed pieces', '报废数量':'Scrapped pieces', '问题说明':'Issue description', '异常类别':'Issue category', '严重程度':'Severity', '表面':'Surface', '尺寸':'Dimension', '裂纹':'Crack', '变形':'Deformation', '装配':'Assembly', '其他':'Other', '轻微':'Minor', '主要':'Major', '严重':'Critical', '添加检验照片':'Add inspection photo', '保存草稿':'Save draft', '草稿已保存':'Draft saved', '无法恢复草稿，请重试':'Unable to restore draft. Retry.', '草稿保存失败，请重试':'Unable to save draft. Retry.',
})
messages.update({
'同步与草稿':'Sync and drafts', '图片上传':'Photo uploads', '没有待上传图片':'No photos to upload', '已上传，待关联检验':'Uploaded, awaiting inspection', '等待上传':'Waiting to upload', '已上传':'Uploaded', '重试上传':'Retry upload', '移除图片':'Remove photo', '确认从待同步列表中移除此图片？':'Remove this photo from the sync queue?', '本机草稿':'Device drafts', '没有未提交草稿':'No unsubmitted drafts', '检验草稿':'Inspection draft', '处置草稿':'Resolution draft', '任务草稿':'Task draft', '刷新云端数据':'Refresh cloud data', '待办与通知':'To do and notifications', '没有待办通知':'No pending notifications', '已读':'Read', '标为已读':'Mark read', '更新通知失败，请重试':'Unable to update notification. Retry.',
'请切回原工作区后重试':'Switch back to the original workspace and retry.', '图片队列已更新，请刷新':'The photo queue has changed. Refresh it.', '图片标识无效':'Invalid photo identifier.', '网络连接失败，请重试':'Connection failed. Retry.', '连接超时，请重试':'Connection timed out. Retry.', '图片已保存，请在同步页面重试上传':'Photo saved. Retry its upload on the Sync page.', '无法读取待同步内容，请重试':'Unable to load sync items. Retry.', '上传失败，请重试':'Upload failed. Retry.', '无法打开草稿，请检查任务权限后重试':'Unable to open this draft. Check task access and retry.', '还有图片待上传，请先在同步页面完成上传':'Upload the remaining photos on the Sync page first.', '网络连接失败，草稿已保留，请重试':'Connection failed. Your draft was kept. Retry.', '任务已更新，请核对当前任务后处理草稿':'The task has changed. Review its current state before continuing this draft.', '恢复草稿':'Restore draft', '重试恢复草稿':'Retry restoring draft', '放弃草稿':'Discard draft', '确认放弃这份未提交的草稿？':'Discard this unsubmitted draft?', '放弃草稿并刷新':'Discard draft and refresh',
'按当前任务继续':'Continue with current task', '保留草稿内容继续编辑，已归档照片不会带入新检验。':'Keep editing this draft with the current task. Archived photos will not be added to a new inspection.', '处置后操作':'Next action', '送交复检':'Send for reinspection', '授权关闭':'Authorized closure', '关闭处置':'Disposition', '报废关闭':'Close as scrapped', '让步接收':'Accept by concession', '授权依据':'Authorization reason',
})
messages.update({
    '全部任务': 'All tasks', '筛选范围': 'Filter scope', '任务号、批次或名称': 'Task ID, batch or name',
    '范围报告': 'Scoped report', '清空筛选': 'Clear filters', '应用筛选': 'Apply filters',
    '任务日期': 'Task dates', '任务起始日期': 'Task start date', '任务结束日期': 'Task end date',
    '平均异常处理时长': 'Average issue resolution time', '查看范围内任务': 'View matching tasks',
    '云端数据': 'Cloud data', '报告预览': 'Report preview', '复制追溯码': 'Copy trace code',
    '没有符合条件的记录。': 'No records match your filters.',
    '尺寸偏差': 'Dimensional deviation', '表面缺陷': 'Surface defect', '装配问题': 'Assembly issue',
})
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
