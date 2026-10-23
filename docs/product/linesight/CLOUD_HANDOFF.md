# 1.1.27 工作台与低资源开发批次

当前仍在sync-delivery / feature/sync-delivery开发。今日数字与任务下钻使用同一设备日历更新范围，服务端支持updated_from/updated_to；全部异常不受今日限制。我的待办三分类、7日首次检验趋势下钻、未读计数修正、未知角色写入入口关闭。129客户端/37后端测试通过，真实HTTPS同范围核验通过；桌面中英文360宽4张PNG明确标记desktop-render，不能当作Android实机证据。

用户要求不用虚拟机/QEMU，后续不得启动模拟器。资源配置已降为Gradle 2 workers/2GB堆、Kotlin in-process，新tool/build_workbench_release.ps1使用no-daemon且不自动安装。升级保留数据与会话恢复仍待真机，不能补写成功。当前普通包/签名结果见acceptance/workbench-batch/validation.json。

下一批继续REL-02数据库/媒体/身份库隔离恢复演练、密码修改/会话与SMTP、完整角色/双语审计、正式签名和剩余逐项验收；总计划仍未完成。

---
# 1.1.26 本机导入、恢复与同步批次

资源约束更新：用户要求停用虚拟机/QEMU；已关闭Android模拟器及闲置构建后台。后续不启动模拟器，使用静态检查、单元测试、云端接口及必要时真机验收。普通8040已构建，不为补截图或升级测试重启模拟器；覆盖升级/回执保留/普通包会话恢复待真机验证。

2026-10-23。**后续功能开发以C:/Users/29668/LineSight-workspaces/sync-delivery / feature/sync-delivery为当前工作区**。bffcf05保存共享界面快照；原product-plan目录仍有界面/素材开发，不得覆盖其后续修改。

- CloudLocalImportPage接本机账户密码授权、预览/确认团队、默认排除示例、源ID重复跳过、分批进度；账户/团队/本机会话变化中止后续批次。导入历史同时保留原始与复核结论。
- CloudPhotoRecovery接持久上下文/文件指针、原账户/团队/任务/阶段恢复到加密队列；WebP原生转PNG、最长边3000，服务端16MP约束保留；同步页提供恢复/放弃。
- CloudAccount分块写入并flush后报告进度，回执前最多99%；CloudDiagnosticsPage检查当前团队云连接，复制白名单支持信息，不含令牌/凭据/记录内容。
- Flutter全量126项、后端36项、Android完整旅程通过，analyze无问题。真实本机SQLite密码授权、HTTPS导入去重、恢复转换/上传回执、16次进度更新、原生剪贴板白名单见acceptance/sync-batch；物理相机与真实系统进程回收待真机。
- 后端备份api-20261023T130044Z，28张原表旧行、7名旧用户、外键及健康检查通过，无新增迁移。HTTPS回读见sync-batch/live-api.json。
- **驱动修正：Flutter drive默认stop会卸载App。此批早期曾触发，现必须显式--keep-app-running。tool/run_sync_journey.ps1固定该参数。** 1.1.25“升级保留数据”证据已更正，交付目录JSON同步更正；不能把那个安装当作数据保留证明。
- 普通入口1.1.26+8040构建、签名/DEX与8039→8040覆盖安装结果以sync-batch/validation.json为准。tool/package_sync_batch.py打包冻结的.artifact-work/sso/sync8040.apk。
- 下一批：角色/双语/小屏与工作台/待办日期口径审计、数据库/媒体/身份恢复演练、正式签名和SMTP；双真机与10外部用户验收仍待实际环境。总计划未完成，保持goal active。

---
# 1.1.25 追溯与检验日期批次

2026-10-23。本批新增任务二维码、复制ID/链接、MLKit扫码和手动输入、冷/热外部链接与统一二级登录门禁、独立检验日期筛选、首次检验日期趋势下钻。云端仍按团队授权，不使用二维码授予权限。

- Flutter全量120项和后端35项通过，Android真实原生解码与路由完整旅程通过，PNG42–48位于acceptance/trace-batch/png。物理相机真机扫码待验收。
- 实际HTTPS通过日期范围、真正的首轮日期和完整历史指标、匿名401及无权限团队404，见trace-batch/live-api.json。
- 云端已部署，备份api-20261023T121652Z；28张原表旧行、7名旧用户、外键和健康检查通过，无新增迁移。
- 检查发现当前工作区另有界面与assets/parts素材改动；保留这些内容，本批只暂存追溯功能相关变更。当前界面增加的共用预览标签和生命周期组件已修复窄屏溢出，移除无数据依据的尺寸/检测结论。普通APK使用当前工作目录构建，不能把功能提交当作APK完整源码快照。
- 正常入口构建/覆盖安装/外部链接验证以acceptance/trace-batch/validation.json为准。tool/package_trace_batch.py负责交付。
- 下一批整批推进受控本机导入、同步诊断/上传百分比、相机恢复，随后角色/双语审计、备份恢复和正式签名。SMTP、双真机与10名外部用户验收仍需实际环境。

---
# 1.1.24 筛选、分类与报告批次

2026-10-23。按产品计划继续成批交付，总计划仍未完成。

- 任务列表/记录/指标/报告/CSV接统一云端筛选：任务号、批次、状态、负责人/未指派、检验人/结论、任务日期、异常类别。空态/加载/刷新及导航返回保留范围；新任务/检验通过云数据版本变化刷新列表。
- 新增类别数量、平均处置时长、分类对应任务下钻、范围报告。报告预览与PDF含来源、团队、筛选范围、追溯编号、完整轮次/模板版本/整改与证据缩略图；CSV增加轮次工件数量。
- Flutter117项通过，后端34项通过（多异常同任务去重及组合范围另复测通过），analyze无问题。
- Android组合筛选/80%首次与100%最终指标/三证据报告预览通过，PNG32–37；普通main分类任务跳转PNG38，中文两页系统PDF及图片PNG39/40通过。补拍时模拟器进程曾退出，原AVD恢复后登录态可恢复；正常入口按任务号筛选出的两轮记录见PNG41。
- 真实HTTPS同范围列表/记录/指标/报告/CSV数值及任务集合一致，见acceptance/query-batch/live-api.json。云部署备份api-20261023T115211Z，28张原表旧行、外键和健康检查通过。
- 普通入口1.1.24+8036覆盖安装及签名检查通过，沿用既有兼容签名。tool/package_query_batch.py负责交付。
- 后续继续：独立检验时间段筛选、趋势日期下钻、二维码/扫码追溯、受控本机导入、同步诊断和百分比、相机恢复、全面双语/窄屏、正式签名、数据与身份恢复演练/SMTP，双真机与10外部用户验收。

---
# 1.1.23 离线与通知批次

2026-10-23。产品计划继续执行，以下为新增交付能力。

- 检验与整改草稿、加密照片待传队列、同步/草稿二级页、明确确认后的冲突续填、通知按用户/任务版本持久已读、管理员授权关闭入口。
- 修复 Android multipart 缺少 Content-Length 导致 WSGI 无法读取附件的问题，新增传输层回归。
- Flutter 全量116项通过，上传修复后14项相关测试通过（含新增1项，总计117项）；后端33项通过；analyze无问题。锁清理调整后队列测试通过。
- Android离线完整旅程通过，截图23至28位于acceptance/offline-batch/png；包括实际上传回执、检验关联、证据查看和通知已读。图片为生成的演示夹具，不代表真机相机验收。
- 0006已部署，备份api-20261023T111325Z，27张原表旧行保留、外键与健康检查通过。
- 普通入口1.1.23+8034构建及覆盖安装/杀进程恢复结果见acceptance/offline-batch/validation.json。仍沿用已有兼容签名。
- 下一批：任务/记录筛选、统计分类下钻、报告来源/范围/证据明细、二维码与受控导入；随后正式签名、恢复演练、SMTP及真机/外部验收。当前上传队列显示状态，百分比仍待接入。

---
# 1.1.22 业务批次最新进展

2026-10-23。下方旧交接保留作历史；以本段为最新进展。总产品计划仍未全部完成。

- 已上线0004/0005：检查模板与快照、数量守恒、SN团队唯一、轮次、异常类别/严重度/责任人、分阶段照片及内容指纹、云记录/指标/报告/待办API。
- 后端32项通过；Flutter113项通过；analyze无问题；真实HTTPS演示流程验证三张分阶段照片、两轮检验、首次80%/最终100%、CSV数值一致。
- Android业务旅程已通过，12张旅程PNG及3张普通main/系统打印PNG位于acceptance/product-batch/png。普通APK覆盖安装、演示登录、会话恢复与中文系统打印预览已验证。首次am start -W曾超时，随后UI可正常读取/登录与重启恢复；不得将该am命令当成启动耗时测量。早期重跑原因是长表单懒构建定位和统计进度条被误当加载指示器；脚本已修正。
- Flutter新增cloud_business.dart接团队创建/加入/邀请/改权/离组、模板版本发布、图片灯箱、指标/CSV/PDF；任务增加批次/模板/负责人/SN/清单/数量/照片与详情记录。任务草稿按身份+工作区保存在secure_storage。
- Android旧默认secure_storage偏好读取发现迁移解密日志；云令牌与新草稿改用独立linesight_cloud_v1 namespace。可读取时迁移旧会话，无法解密则重新登录，退出标记禁止再恢复旧会话。该改动进入普通main构建，普通入口演示登录与杀进程恢复实际通过；集成截图构建在其之前。
- API部署备份：/var/backups/linesight/identity/api-20261023T103817Z，25张原表旧行全部保留，外键与健康检查通过。
- 已交付普通入口1.1.22+8032，沿用已有签名以支持覆盖安装；正式REL-01签名未完成。构建/打包脚本tool/package_product_batch.py，私有输入.artifact-work/sso/demo-build.json不得提交。
- 尚待：检验离线草稿、照片加密重试队列、持久通知已读、完整过滤/分布下钻、授权关闭客户端入口、二维码、同步/诊断页面、正式签名、数据库/图片/身份库恢复演练、SMTP配置，以及双真机和10外部用户测试。按用户要求继续整批推进，不逐页打磨。

---

# 最新云端开发交接

2026-10-23。总目标仍为逐项完成原产品计划并截图，未完成，不得标记总目标完成。

工作区`C:/Users/29668/LineSight-workspaces/product-plan`，分支`feature/product-plan`。基线`8b7147d`，权限基础`7572f92`，新代码见后续云身份/任务提交。Excel为主表56项，0项已验收；`update_cloud_backlog.mjs`导入原表更新，CSV仅镜像。

## 实际已上线

- Keycloak26.8.1 + PostgreSQL17，以Podman Compose/systemd运行。issuer为`https://47.111.81.94/sso/realms/linesight`，Caddy转发loopback8081。
- 普通客户端使用授权码+PKCE S256，无密码授权；共享演示客户端单独配置，只访问独立演示团队。
- API验证RS256/issuer/audience/azp/exp/iat/sub并每请求introspection；退出即时失效，身份服务故障503；旧客户注册/密码登录410。
- 5个原账户保留Argon2原密码并绑定原Django用户；不按登录用户声称的username/email关联。临时账号真实导入登录验证通过。
- 部署备份源码/环境/SQLite，核对原23表全部旧行不变。脚本曾遇系统旧SQLite、健康检查Host错误，均自动回滚；修正后成功上线。中断导入恢复通过可信密码表示精确比对，不靠同名授权。
- migration0003上线：任务version、JobMutation幂等回执、事件job/version/details。云端状态/检验/异常处理要求version和Idempotency-Key，事务CAS，409带当前任务；不能PATCH绕过异常关闭/复检，授权关闭需owner+处置+依据，处理结果不可覆盖，复检新增轮次，关闭不可重开。
- 真实HTTPS并发验证：一个成功一个409；重复检验/处理幂等、双轮次、不覆盖、事件版本均通过。证据在`acceptance/sso/live-workflow-verification.json`。

## Flutter实际变化

- main使用CloudShell：普通与团队统一云身份，登录为二级路由；访客不读保护本机数据；工作区切换/资料/只读成员/托管改密/退出。AppAuth+secure_storage，会话恢复与本机初始化在无反光粒子动画期间并行。
- 新云任务搜索/状态筛选/新建/详情概览质检异常历史/打印送检/登记检验/异常处理/复检；冲突保留说明并要求返回刷新。二态检验仍非完整QC清单。
- 请求key已添加固定前缀，避免旧uid偶发15字符被服务端拒绝；登录过期隐藏任务详情/命令表单/成员缓存，新增UI回归测试。
- 最新Flutter全量113项通过（含过期详情隐私门禁、冲突保留输入、双语窄屏）；后端30项通过；静态检查通过。真实云API与两条Android旅程亦通过。
- Android云登录旅程再次通过（构建8027），7张真实PNG已更新；成员页已使用客户显示名称，旧内部映射名截图已替换。
- Android完整任务旅程首次因系统键盘改变坐标导致点击未命中，加入收起键盘/等待后复测通过（41秒），新增9张真实PNG（08–16），覆盖新建/状态/异常/处理/双轮次/历史/筛选。日志`.artifact-work/sso/android-workflow-journey.log`。

## 位置/命令

- 部署结构与恢复：`deploy/sso/README.md`。验证脚本：`verify_keycloak.py`、`verify_legacy_password_import.py`、`verify_cloud_api.py`、`verify_live_workflow.py`。
- API远端`/opt/linesight/backend`，venv`/opt/linesight/venv`；环境`/etc/linesight/linesight.env`；DB`/var/lib/linesight/linesight.sqlite3`。
- 最近备份`/var/backups/linesight/identity/api-20261023T100339Z`，原24表旧行全保留；后续部署脚本仍按同样机制备份和核验。
- staging`/opt/linesight-identity/api-cutover`。构建私密输入`.artifact-work/sso/demo-build.json`，不得打印/提交；仅演示身份可编入App，无基础设施或管理员密钥。
- Gradle用户代理127.0.0.1:7897目前未运行，显式传`-Dhttp.proxyHost= -Dhttps.proxyHost=`及`-I ../tool/gradle_mirrors.init.gradle`；显式Gradle还需私下编码dart-defines传入。
- emulator-5554已测试构建8026/8027；正常main入口测试包版本1.1.21+8030正在构建。后续更新不能降级，不卸载/不清数据。集成测试APK不能交付为正常客户APK；正式main配置须在release构建前重新生成。
- SSH沿用现有`~/.ssh/linesight-ali-baot.pem`，不输出凭证。

## 继续顺序

1. 完成Android任务旅程，替换成员页截图，记录构建与日志；生成正常main入口测试APK。当前Android release配置仍debug签名，REL-01未完成。
2. 统一身份下团队创建/加入/邀请/改权移除/同步状态及真实Android角色撤权回归。
3. DAT-02/05、QC模板三态清单、工件数量/批次/SN、证据绑定检验、异常分类/责任人/前后图；当前不可当作完整QC验收。
4. 工作台趋势/我的待办/洞察、按工件口径报告CSV/PDF、通知扫码、离线草稿/上传/冲突恢复。
5. SMTP重置邮件，身份库定时备份与恢复演练，正式签名无损升级、诊断、双语全流程及客户文案审阅。
6. 两台真实Android及至少10名外部用户尚缺，不伪造、不标记完成；其他开发继续。

不要因SSO与基本任务链通过而缩小总目标或将未完成依赖标记已验收。原文51项+追加5项均保留固定ID逐项推进。
