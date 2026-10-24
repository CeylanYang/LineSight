# LineSight 交付状态（2026-10-24）

客户端交付基线为 **1.1.54+8078，内容版本 5**。新增 OTA 模块启动异常报告过滤，保留开屏等待上限与此前会话修复；已有 8078 不需要重新安装 APK。当前官网为 https://99ai.pronhubcn.com/ ，同时保留 `/linesight/`。App API、Keycloak issuer 和原生 OAuth 回调未迁移。

## 本次新增完成

| 项目 | 验证结果 | 证据 |
| --- | --- | --- |
| 原生管理员权限补验（部分） | 实际 App 二级登录 → Keycloak → AppAuth 回调，确认临时管理员身份和独立团队；6 组页面 XML/PNG 校验覆盖团队邀请/成员菜单、任务创建、打印配置及模板发布入口。模拟器宿主两次退出，四角色整体验收未通过；4 个临时身份、4 个 API 用户及 5 个工作区已清理，未修改客户团队 | acceptance/roles69-batch/partial-validation.json、cleanup.json |
| 原生崩溃后的 OTA 回退 | 独立 API34 x86_64：正常 force-stop 保留补丁；首帧完成后对精确 App PID 注入 SIGSEGV，Android 记录 reason=5/status=11。下一次启动移除、拉黑、拒绝再次应用并恢复工作台。未修改线上或客户数据 | acceptance/native68-batch/validation.json、exit-and-ui-evidence.json |
| OTA 启动异常报告与故障回退 | 修复开源模块先于 App 过滤器向原生传递原始异常的问题。独立 API34 x86_64 实际加载框架/异步故障 AOT：固定类别到达原生、移除、拉黑、再次应用同补丁拒绝、冷启动恢复；无原始标记。正常正式 OTA4 内容 5 生效及演示登录保留；466 测试通过 | acceptance/ota67-batch/validation.json、delivery.json |
| 正式内容 4 二级页 | 配方/打印配置/配置预填新建任务/模板/账户/卡片/无 NFC 提示及取消/本机导入授权入口/操作成员团队页面；14 组原生截图/XML。未提交任务，未改客户数据 | acceptance/secondary66-batch/validation.json |
| 官网安装包 | 正式版及旧体验版兼容升级包更新为 1.1.54 内容 5；旧 URL 转向兼容升级。服务器侧域名 HTTPS 完整下载与交付哈希一致；本机此前 TLS EOF，独立客户端访问及浏览器布局待验 | acceptance/ota67-batch/public-https.json |
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
| APK 邮件往返 | 从 App 找回密码，经外部邮箱打开链接，再回 App 登录；服务端和 PKCE 流程已通过 |
| 原生日志 | AppAuth 三类令牌故障通过；内容 5 已在正式 Android 基础包加载实际框架/异步故障 AOT，覆盖模块报告到原生日志的路径。仍需其他插件直接日志、系统崩溃及真实设备审计 |
| NFC/摄像头/扫码/触觉 | 需要真实 Android 手机及实际卡片。模拟器和服务器测试不能证明硬件工作正常 |
| 双真机协作 | 两部手机跨账号完成创建、指派、检验、异常、复检、报告及权限一致性验证 |
| 外部用户试用 | 至少 10 名外部用户完成任务及反馈复测 |
| 灾备 | 第二台主机完整恢复启动和生产切换演练；APK/OTA 签名密钥及备份解密钥需独立异地托管 |
| OTA 扩展验收 | 内容 5 正式 OTA4 运行、启动期 Dart 故障及 API34 x86_64 首帧后原生 SIGSEGV 的移除/拉黑/拒绝再次应用通过；仍需最新预览原生补验、物理 ARM 设备、ANR 及其他 Android API 覆盖 |

测试收件人已确认收到“LineSight 邮件服务连接测试”。用户目前未提供真机。本阶段继续处理可独立完成的软件及模拟器验收，以上项目保留在台账，不计作完成。最新 native60 补验覆盖部分二级页及导出路径，未将“所有页面与角色”整体标记通过。

Excel 主表本次仅更新 SEC-05、COL-01、COL-02、REL-01、REL-02、REL-04、QA-02、QA-04、SSO-03 的状态及证据。28 个值变更通过 OOXML 对比；工作表结构、样式、公式、验证及其他原生部分保持，CSV 同步。未将“待验收”改写成“没有实现”。
