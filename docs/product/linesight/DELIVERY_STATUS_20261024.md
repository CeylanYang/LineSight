# LineSight 交付状态（2026-10-24）

客户端交付基线为 **1.1.54+8078，内容版本 5**。新增 OTA 模块启动异常报告过滤，保留开屏等待上限与此前会话修复；已有 8078 不需要重新安装 APK。当前官网为 https://99ai.pronhubcn.com/ ，同时保留 `/linesight/`。App API、Keycloak issuer 和原生 OAuth 回调未迁移。

## 本次新增完成

原生补验第 75/76 批已有实质进展：正式签名 8078→8079 保留数据升级通过，首次安装时间不变；演示登录及 13/3/13 任务数量保留，强制停止后冷启动仍保留；应用更新页实际显示 1.1.55 / 内容版本 5。候选中的 App 二级登录→浏览器→AppAuth 回调已载入独立临时管理员身份。证据见 `acceptance/upgrade75-batch/upgrade.json`、`validation.json` 与配对 PNG/XML。线上仍为 8078，候选尚未发布。

原模拟器 36.2.12 与独立 37.2.12 的软件渲染运行均曾以 `0xC0000005` 退出；本次在诊断监控下取得上述证据后再次崩溃，ProcDump 成功捕获宿主异常。异常地址不属于已载入模块，崩溃线程栈中有 `gles_swiftshader/libGLESv2.dll` 地址；这仅为软件图形后端线索，尚不能确定根因。原始转储仅保存在本机私有目录。切换 AMD 显卡后端已启动，但长期稳定性仍待验证。第 76 批管理员配置/模板等 4 组页面有配对证据，完整角色页面验收未完成；4 个临时身份、4 个 API 用户及 5 个工作区已清理，客户团队未修改。邮件测试收件人再次确认已收到。

| 项目 | 验证结果 | 证据 |
| --- | --- | --- |
| 原生插件日志修复候选 | release R8 及正式打包 DEX 检查：旧内容 5 APK 保留 1,656 处 Log、24 处 printStackTrace；1.1.55+8079 两种签名候选均归零，474 项完整 Flutter 测试通过。8 张版本号差异截图逐一审阅并按版本归档，旧证据未覆盖；两签名 native/资源/资产/引擎指纹相同。正式签名升级保留、冷启动、版本页及浏览器回调已补验；兼容签名升级、剩余角色页面及候选回退未完成。候选未发布，8078 线上基线和 OTA 未修改 | acceptance/privacy74-batch/validation.json、full-test-result.txt；upgrade75-batch/upgrade.json |
| 四角色配置/团队导航回归 | 360px、中英文、管理员/主管/操作/只读 8 组组件导航测试通过：配置和模板管理入口、任务表单入口权限及返回原详情、团队邀请及菜单权限、零写入。该测试文件静态检查通过；原生模拟器再次在登录前退出，原生四角色未完成，临时身份及数据均清理 | acceptance/roles72-batch/validation.json、widget-tests.txt、cleanup.json |
| 官网手机布局 | 已发布独立手机样式：700px 及以下改为纵向布局，首屏提供正式版/兼容升级下载按钮，48px 高、16px 字号；正文及表单按手机尺寸显示。独立 Chrome 公网 320/390/700/1440px 无横向溢出、无脚本异常，手机任务演示交互正常；桌面保留原布局 | acceptance/portal71-batch/deployment.json、live/validation.json、截图 |
| 原生管理员权限补验（部分） | 实际 App 二级登录 → Keycloak → AppAuth 回调，确认临时管理员身份和独立团队；6 组页面 XML/PNG 校验覆盖团队邀请/成员菜单、任务创建、打印配置及模板发布入口。模拟器宿主两次退出，四角色整体验收未通过；4 个临时身份、4 个 API 用户及 5 个工作区已清理，未修改客户团队 | acceptance/roles69-batch/partial-validation.json、cleanup.json |
| 原生崩溃后的 OTA 回退 | 独立 API34 x86_64：正常 force-stop 保留补丁；首帧完成后对精确 App PID 注入 SIGSEGV，Android 记录 reason=5/status=11。下一次启动移除、拉黑、拒绝再次应用并恢复工作台。未修改线上或客户数据 | acceptance/native68-batch/validation.json、exit-and-ui-evidence.json |
| OTA 启动异常报告与故障回退 | 修复开源模块先于 App 过滤器向原生传递原始异常的问题。独立 API34 x86_64 实际加载框架/异步故障 AOT：固定类别到达原生、移除、拉黑、再次应用同补丁拒绝、冷启动恢复；无原始标记。正常正式 OTA4 内容 5 生效及演示登录保留；466 测试通过 | acceptance/ota67-batch/validation.json、delivery.json |
| 正式内容 4 二级页 | 配方/打印配置/配置预填新建任务/模板/账户/卡片/无 NFC 提示及取消/本机导入授权入口/操作成员团队页面；14 组原生截图/XML。未提交任务，未改客户数据 | acceptance/secondary66-batch/validation.json |
| 官网安装包 | 正式版及旧体验版兼容升级包更新为 1.1.54 内容 5；旧 URL 转向兼容升级。本机独立 Chrome 正常 TLS 校验：首页及 `/linesight/` 返回 200，桌面正式版/手机尺寸兼容版按钮均下载完整 75,547,520 字节，SHA256 与交付一致；旧路径两下载入口 HEAD 正常。三组页面无脚本异常或横向溢出；手机仍整页缩放、控件偏小，可读性待改善 | acceptance/ota67-batch/public-https.json；acceptance/portal70-batch/browser.json、截图 |
| 邮件找回密码 | 正式 Keycloak → 自托管 Postfix → 163 SMTP465 → 真实邮箱。重置、新密码 PKCE 登录、旧密码拒绝、重置链接重放拒绝通过 | acceptance/mail57-batch/production-reset.json |
| 内容版本 2 原生补验 | 演示团队登录、CSV 保存、9 页 PDF 系统打印、导出返回、同步诊断及部分英文二级页；11 组截图/XML 与导出指标校验通过 | acceptance/native60-batch/validation.json |
| Flutter 未捕获错误日志 | 正式版本框架及根 isolate 异步错误只输出固定来源/类别。463 项测试、静态检查通过，预览 OTA5 冷启动内容 3、演示登录保留；正式 OTA2 已发布 | acceptance/runtime62-batch/validation.json |
| 开屏等待及正式签名运行 | 原生可见回调最多等两秒，保留 GPU 等待及正常动画。464 项测试、静态检查通过；新正式 AVD 首次打开、演示登录、正式 OTA3 冷启动内容 4 通过 | acceptance/startup64-batch/validation.json |
| 失效会话恢复 | 修复 AppAuth 旧错误字段读取问题。真实模拟器由通用失败恢复为“登录已过期”，点击进入二级登录页；预览 OTA4、正式 OTA1 已发布 | acceptance/refresh59-batch/validation.json |
| 关闭注册 | 正式邮件配置后仍关闭，原有账号密码未更改，一次性验收账号已删除 | acceptance/mail57-batch/production-smtp.json |
| 即时撤权 | 真实 PKCE 四角色矩阵，降权旧令牌 401、新只读令牌写入 403、移除后 404，最后管理员离组 409 | acceptance/roles56-batch/live-role-matrix.json |
| 服务端日志 | Django 不记录原始错误消息、请求凭据、查询及正文。生产探针的敏感标记未入 journal，保留请求编号及代码位置 | acceptance/privacy58-batch/live-logs.json |
| 原生认证故障日志补验 | 冻结 8078 中的 AppAuth：invalid_grant、非 JSON、网络 IOException 三类内存模拟故障，回调包含测试标记，进程 29 行日志未出现标记 | acceptance/privacy61-batch/native-appauth.json |
| 反向代理日志 | Caddy 官方 filter encoder；不可达上游 502 试验未记录请求敏感值，生产官网及 API HTTPS 正常 | acceptance/privacy58-batch/proxy-logs.json |
| 异机备份与保留 | 自动 AES-256-GCM 备份、逐文件及数据库校验、30 天及周/月保留。部署配置包括 SMTP 授权与 DKIM 私钥，公开证据不含密钥 | acceptance/mail57-batch/relay-config-backup.json |

最近服务端 **101 项测试通过**。内容版本 5 通过 **466 项 Flutter 测试及静态检查**，包含新增的开屏回调丢失回归、4 项错误日志过滤及此前 6 项 AppAuth 错误兼容及会话保留回归。OTA 基线已在 API34 x86_64 模拟器验证后台下载、冷启动生效、签名回滚及登录保留，见 `acceptance/ota54-batch/validation.json`；内容版本 2 又验证实际过期会话及原生登录入口。内容版本 3 的预览 OTA、内容版本 4 的正式签名首次打开和正式 OTA 均有运行证据。最新两种签名 APK 位于 `D:/ENT207/deliverables/LineSight-1.1.54-content5/`，保留旧交付作为历史基线。

163 为外部中继服务；Keycloak、Postfix、Mailpit、OpenDKIM 和 OTA 服务由我们部署。阿里云轻量应用服务器不支持出站 25 发信，因此入站放行 25 不会启用直投。当前发件地址使用授权的 163 邮箱。成员找回密码前须绑定本人可访问的邮箱，不会批量共用测试收件邮箱。

## 尚待完成

| 工作 | 当前缺少的验收 |
| --- | --- |
| 最终 APK 页面及权限 | 正式内容 4 已补验配置、模板、账户、卡片、本机导入授权入口和操作成员团队页面；仍需剩余二级页、中英文小屏、所有角色的入口/返回/撤权，不能以本批代替全部原生验收 |
| 官网真实手机补验 | 浏览器手机视口的纵向布局、首屏下载控件尺寸及任务交互已通过；仍需真实手机浏览器与用户操作反馈，不能以模拟视口代替实机易用性验收 |
| APK 邮件往返 | 从 App 找回密码，经外部邮箱打开链接，再回 App 登录；服务端和 PKCE 流程已通过 |
| 原生日志 | 1.1.55+8079 候选已移除 DEX 中直接 Log v/d/i/w/e/println 及 printStackTrace 调用；需候选原生回归和正式发布后才能覆盖客户版本。native 库、反射/其他日志 API、系统崩溃及真实设备审计仍待完成。内容 5 的 Dart 异常及 AppAuth 故障证据保留 |
| NFC/摄像头/扫码/触觉 | 需要真实 Android 手机及实际卡片。模拟器和服务器测试不能证明硬件工作正常 |
| 双真机协作 | 两部手机跨账号完成创建、指派、检验、异常、复检、报告及权限一致性验证 |
| 外部用户试用 | 至少 10 名外部用户完成任务及反馈复测 |
| 灾备 | 第二台主机完整恢复启动和生产切换演练；APK/OTA 签名密钥及备份解密钥需独立异地托管 |
| OTA 扩展验收 | 内容 5 正式 OTA4 运行、启动期 Dart 故障及 API34 x86_64 首帧后原生 SIGSEGV 的移除/拉黑/拒绝再次应用通过；仍需最新预览原生补验、物理 ARM 设备、ANR 及其他 Android API 覆盖 |

测试收件人已确认收到“LineSight 邮件服务连接测试”。用户目前未提供真机。本阶段继续处理可独立完成的软件及模拟器验收，以上项目保留在台账，不计作完成。最新 native60 补验覆盖部分二级页及导出路径，未将“所有页面与角色”整体标记通过。

Excel 主表本次仅更新 SEC-05、COL-01、COL-02、REL-01、REL-02、REL-04、QA-02、QA-04、SSO-03 的状态及证据。28 个值变更通过 OOXML 对比；工作表结构、样式、公式、验证及其他原生部分保持，CSV 同步。未将“待验收”改写成“没有实现”。
