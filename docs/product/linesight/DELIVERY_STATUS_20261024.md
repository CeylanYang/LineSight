# LineSight 交付状态（2026-10-24）

客户端交付基线为 **1.1.54+8078，内容版本 2**。服务端变更和本次 Dart 会话修复通过 OTA 生效，已有 8078 不需要重新安装 APK。当前官网为 https://99ai.pronhubcn.com/ ，同时保留 `/linesight/`。App API、Keycloak issuer 和原生 OAuth 回调未迁移。

## 本次新增完成

| 项目 | 验证结果 | 证据 |
| --- | --- | --- |
| 邮件找回密码 | 正式 Keycloak → 自托管 Postfix → 163 SMTP465 → 真实邮箱。重置、新密码 PKCE 登录、旧密码拒绝、重置链接重放拒绝通过 | acceptance/mail57-batch/production-reset.json |
| 失效会话恢复 | 修复 AppAuth 旧错误字段读取问题。真实模拟器由通用失败恢复为“登录已过期”，点击进入二级登录页；预览 OTA4、正式 OTA1 已发布 | acceptance/refresh59-batch/validation.json |
| 关闭注册 | 正式邮件配置后仍关闭，原有账号密码未更改，一次性验收账号已删除 | acceptance/mail57-batch/production-smtp.json |
| 即时撤权 | 真实 PKCE 四角色矩阵，降权旧令牌 401、新只读令牌写入 403、移除后 404，最后管理员离组 409 | acceptance/roles56-batch/live-role-matrix.json |
| 服务端日志 | Django 不记录原始错误消息、请求凭据、查询及正文。生产探针的敏感标记未入 journal，保留请求编号及代码位置 | acceptance/privacy58-batch/live-logs.json |
| 反向代理日志 | Caddy 官方 filter encoder；不可达上游 502 试验未记录请求敏感值，生产官网及 API HTTPS 正常 | acceptance/privacy58-batch/proxy-logs.json |
| 异机备份与保留 | 自动 AES-256-GCM 备份、逐文件及数据库校验、30 天及周/月保留。部署配置包括 SMTP 授权与 DKIM 私钥，公开证据不含密钥 | acceptance/mail57-batch/relay-config-backup.json |

最近服务端 **101 项测试通过**。内容版本 2 通过 **459 项 Flutter 测试及静态检查**，新增 6 项 AppAuth 错误兼容及会话保留回归。OTA 基线已在 API34 x86_64 模拟器验证后台下载、冷启动生效、签名回滚及登录保留，见 `acceptance/ota54-batch/validation.json`；内容版本 2 又验证实际过期会话及原生登录入口。最新两种签名 APK 位于 `D:/ENT207/deliverables/LineSight-1.1.54-content2/`，保留旧交付作为历史基线。

163 为外部中继服务；Keycloak、Postfix、Mailpit、OpenDKIM 和 OTA 服务由我们部署。阿里云轻量应用服务器不支持出站 25 发信，因此入站放行 25 不会启用直投。当前发件地址使用授权的 163 邮箱。成员找回密码前须绑定本人可访问的邮箱，不会批量共用测试收件邮箱。

## 尚待完成

| 工作 | 当前缺少的验收 |
| --- | --- |
| 最终 APK 页面及权限 | 在 8078 上覆盖剩余二级页、中英文小屏、所有角色的入口/返回/撤权；历史页面和 API 测试不能代替全部原生验收 |
| APK 邮件往返 | 从 App 找回密码，经外部邮箱打开链接，再回 App 登录；服务端和 PKCE 流程已通过 |
| 原生日志 | Android 系统和第三方插件异常输出的实际抓取审计；本批服务端过滤不代表这些日志已完成验收 |
| NFC/摄像头/扫码/触觉 | 需要真实 Android 手机及实际卡片。模拟器和服务器测试不能证明硬件工作正常 |
| 双真机协作 | 两部手机跨账号完成创建、指派、检验、异常、复检、报告及权限一致性验证 |
| 外部用户试用 | 至少 10 名外部用户完成任务及反馈复测 |
| 灾备 | 第二台主机完整恢复启动和生产切换演练；APK/OTA 签名密钥及备份解密钥需独立异地托管 |
| OTA 扩展验收 | 正式渠道运行、物理 ARM 设备与故意坏补丁的自动崩溃回滚 |

用户目前未提供真机。本阶段继续处理可独立完成的软件及模拟器验收，以上项目保留在台账，不计作完成。

Excel 主表本次仅更新 SEC-05、COL-01、COL-02、REL-01、REL-02、REL-04、QA-02、QA-04、SSO-03 的状态及证据。28 个值变更通过 OOXML 对比；工作表结构、样式、公式、验证及其他原生部分保持，CSV 同步。未将“待验收”改写成“没有实现”。
