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
messages.update({
    '任务二维码': 'Task QR code', '复制任务ID': 'Copy task ID', '复制追溯链接': 'Copy trace link',
    '任务追溯': 'Task trace', '扫码追溯': 'Scan task code', '输入追溯号': 'Enter trace code',
    '输入任务ID或追溯链接': 'Enter task ID or trace link', '追溯号无效，请检查后重试': 'Invalid trace code. Check it and try again.',
    '当前账户无法访问该任务': 'This account cannot access this task.', '无法打开任务，请重试': 'Could not open this task. Try again.',
    '无法打开任务，请检查网络后重试': 'Could not open this task. Check your connection and retry.',
    '请扫描LineSight任务二维码': 'Scan a LineSight task QR code.',
    '相机不可用，请允许相机访问或输入追溯号': 'Camera unavailable. Allow camera access or enter a trace code.',
    '工件预览': 'Part preview', '外观参考': 'Surface reference',
    '检验日期': 'Inspection dates', '检验起始日期': 'Inspection start date', '检验结束日期': 'Inspection end date',
    '首次检验日期（UTC）': 'First inspection date (UTC)', '结束日期需要晚于开始日期': 'The end date must follow the start date.',
})
messages.update({
    '导入本机记录':'Import device records','授权、预览并导入历史记录':'Authorize, preview and import historical records',
    '账户或工作区已变化，请重新预览':'Your account or workspace changed. Preview again.',
    '目标团队':'Destination team','使用本机工程师或管理员账户授权读取记录':'Authorize with a device engineer or administrator account',
    '本机用户名':'Device username','本机密码':'Device password','授权并预览':'Authorize and preview',
    '确认导入':'Confirm import','将 {0} 条记录导入 {1}':'Import {0} records into {1}',
    '再次导入':'Import again','团队历史记录':'Team historical records','当前角色仅可查看记录':'Your role can only view records',
    '请切回拍照时的账户和团队后恢复照片':'Switch to the original account and team to recover this photo.',
    '照片正在处理中，请稍后':'A photo is being processed. Please wait.',
    '请先在同步页面恢复上次照片':'Recover the previous photo on the sync page first.',
    '照片未能恢复，请重新拍照':'The photo could not be recovered. Take it again.',
    '已恢复 {0} 张照片，请在同步页面上传':'Recovered {0} photos. Upload them on the sync page.',
    '恢复照片':'Recover photos','放弃照片恢复':'Discard photo recovery','确认放弃上次未完成的照片？':'Discard the previous unfinished photo?',
    '已放弃照片恢复':'Photo recovery discarded','没有可恢复的照片':'No photos to recover',
    '同步诊断':'Sync diagnostics','云端连接':'Cloud connection','连接正常':'Connected','需要处理':'Needs attention',
    '检查时间':'Last checked','检查连接':'Check connection','复制诊断信息':'Copy diagnostics','诊断信息已复制':'Diagnostics copied',
    '连接未完成，请检查网络或重新登录':'Connection failed. Check your network or sign in again.',
    '正在上传':'Uploading',
})
messages.update({'质量概览':'Quality overview','今日按进度更新时间统计':'Today by progress update time','今日待检':'Awaiting inspection today','今日已关闭':'Closed today','我的待办':'My to-dos','待异常处理':'Issues to resolve','暂无待办':'No to-dos','近7日首次检验':'First inspections · 7 days','合格数 / 送检数':'Passed / inspected','暂无检验数据':'No inspection data','进度更新起始日期':'Progress updated from','进度更新结束日期':'Progress updated to'})
messages.update({'工作区已切换':'Workspace changed','返回工作台后重新打开页面':'Return to the workbench and reopen this page.','账户或团队已切换，请重新打开页面':'Your account or team changed. Reopen this page.','更新当前账户的登录密码':'Update the password for this account'})
messages.update({
'下载当前范围的明细数据':'Download details for this scope','与团队同步质检进度、照片证据与质量报告。':'Sync inspection progress, photo evidence and quality reports with your team.',
'个人工作区':'Personal workspace','个任务':'tasks','个模板':'templates','为每个工件登记独立检验结论':'Record a separate inspection result for each piece','云端快照':'Cloud snapshot','人':'people','仅团队所有者':'Team owner only','仅团队管理员':'Team administrators only','从登记到关闭的平均用时':'Average time from issue creation to closure',
'任务':'Tasks','任务与检验同步':'Task and inspection sync','任务已被其他人更新，请选择如何处理这份草稿。':'This task was updated by someone else. Choose how to continue with this draft.','任务清单':'Task list','份':'reports','份草稿':'drafts','使用团队账号继续':'Continue with your account','使用系统打印服务生成 PDF':'Use system printing to save a PDF','例如：外观与尺寸终检':'For example: final appearance and dimension check','偏好设置':'Preferences','全部通知':'All notifications','切换权限会立即生成新的邀请码':'Changing the role creates a new invitation code','创建生产质检单':'Create a production inspection task','刷新数据':'Refresh data','协作团队':'Team workspace','历史检验记录保留原模板快照':'Historical inspections retain their original checklist','原图与边缘参考双重归档':'Original photos and edge references','发布模板后可快速创建标准化质检任务。':'Publish a checklist to create standardized inspection tasks.',
'发现异常时将生成异常单，请补充类别与说明。':'A failed result creates an issue. Add its category and description.','同步生产任务、检验记录与质量报告，离线操作也会安全保留。':'Sync tasks, inspections and reports, and keep drafts when offline.','名成员':'members','团队与账户':'Team and account','团队权限隔离':'Team access','团队质量趋势与导出':'Team quality trends and exports','在应用内查看带照片的报告快照':'View a report with photos in the app','基本信息':'Basic information','填写工件信息，草稿会自动保存在本机。':'Enter the piece details. Your draft is saved on this device.','处理阶段':'Resolution stage','导出 CSV':'Export CSV','导出与报告':'Reports and exports','尚未添加照片，建议拍摄缺陷与整体外观。':'Add photos of the defect and overall appearance.','工作区':'Workspace','已按 SN 自动统计':'Counts calculated from serial numbers','已添加 {0} 张照片，提交后随检验记录归档。':'{0} photos added. They will be saved with the inspection.','已清空':'Cleared','张':'photos','张待上传':'photos pending upload','当前筛选范围内没有任务。':'No tasks match these filters.','当前范围内暂无检验数据':'No inspection data in this scope','当前范围内没有登记异常':'No issues recorded in this scope','待上传图片':'Photos pending upload','待检工件':'Pieces awaiting inspection','快捷操作':'Quick actions','成员':'Members','所有照片均已同步至云端':'All photos synced','打印阶段':'Printing stage','按任务数量排序':'Sorted by task count','按工作区版本管理':'Workspace checklist versions','按工作区隔离数据与操作权限':'Workspace data and access','按当前筛选范围统计':'Metrics for the current filters','提交后写入任务审计记录，可继续补充照片。':'Save this action to the task history. You can add photos later.','支持双指缩放与拖动查看细节':'Pinch to zoom and drag to see details','新版本将覆盖当前默认检查项':'The new version becomes the default checklist','最近 7 天':'Last 7 days','最近动态':'Recent activity','未关闭异常':'Open issues','未命名成员':'Unnamed member','未指派':'Unassigned','未读':'Unread','本地优先的质量追溯':'Quality records at hand','本次检验未上传照片':'No photos for this inspection','本次检验未记录检查项。':'No checklist items recorded for this inspection.','条':'items','条待处理通知':'pending notifications','条提醒':'reminders','条未读':'unread','核心指标':'Key metrics','检查项数量符合发布要求':'Checklist item count is valid','检查项目':'Checklist items','检验模板':'Inspection checklist','检验结果':'Inspection result','检验阶段':'Inspection stage','模板信息':'Checklist information','每行一项（3 至 6 项）':'One item per line (3–6 items)','没有待办通知，新的异常与复检会显示在这里。':'New issues and reinspections will appear here.','没有待处理通知':'No pending notifications','没有未提交的草稿':'No unsubmitted drafts','演示数据':'Demo data','演示账号不支持修改账户信息。':'Account details cannot be changed for the shared demo.','点击日期查看当日任务':'Select a date to view its tasks','照片证据':'Photo evidence','照片证据留存':'Photo evidence','状态、轮次和逐件 SN 实时更新':'Live status, inspection rounds and serial numbers','现场':'On site','生产质量工作台':'Production quality workbench','生成时间':'Generated at','登录后将自动载入当前工作区的任务与通知。':'Sign in to load tasks and notifications for your workspace.','登录后查看任务与检验记录。':'Sign in to view tasks and inspections.','登录后管理账户信息与密码。':'Sign in to manage your account and password.','登录团队工作区':'Sign in to your workspace','登录安全':'Sign-in security','离线照片与未提交内容':'Offline photos and unsubmitted work','离线草稿':'Offline drafts','简体中文 / English':'English / Simplified Chinese','统一检查口径，模板版本随检验记录一起归档。':'Use consistent checks and keep each checklist version with its inspection.','补充测量值、环境或沟通信息':'Add measurements, conditions or handover notes','证据':'Evidence','证据照片':'Evidence photos','说明处理方式、结果与后续安排':'Describe the action, result and next steps','请填写 3 至 6 个检查项':'Enter 3–6 checklist items','账户信息':'Account information','跳转到与当前筛选一致的任务列表':'Open the task list with the same filters','输入内容会自动保存在本机':'Your changes are saved on this device','追踪与备注':'Traceability and notes','逐轮追溯检验结论、检验人与照片证据。':'Review results, inspectors and photo evidence for every round.','逐项核对检查项，并确认合格与异常数量。':'Check each item and confirm passed and failed quantities.','通知列表':'Notifications','通过率与异常趋势':'Pass rates and issue trends','邀请成员与管理权限':'Invite members and manage roles','重新加载':'Reload','重试':'Retry','随检验记录归档':'Saved with the inspection','需要登录':'Sign-in required','项':'items',
})
messages.update({'表面划痕、装配间隙、关键尺寸、标识与批次':'Surface scratches, assembly fit, key dimensions, labels and batch'})
messages.update({'上传照片':'Photo uploaded','未记录操作者':'Actor not recorded','任务版本':'Task version','记录编号':'Record ID','照片阶段':'Photo stage','检验照片':'Inspection photo','送检数':'Inspected','合格数':'Passed','异常数':'Failed','报废数':'Scrapped'})
messages.update({'逐件检验结果':'Per-piece inspection results'})
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
