# OTA 后连接故障与股票入口修复

2026-10-25，内容版本32。针对用户报告的“连接未完成”修复。

## 原因与修复

上一版将 API、OIDC 和 OTA 地址切到域名后，本机实际 Dart HTTPS 在域名 TLS 握手阶段被断开；同一机器的 Schannel 请求也失败，而 Chromium/Node 及服务器侧验证成功。服务端抓包观察到 ClientHello 后、服务器 TLS 响应前的连接重置。浏览器验证没有覆盖应用实际网络栈，导致漏检。此现象不能单凭抓包归因到某个运营商或中间设备。

- 所有应用内 Dart 网络入口统一使用 `service_transport.dart`：账号、演示登录、刷新、工作区、照片上传/下载、配置、素材和 OTA 均覆盖。
- 仅对既有生产域名的 HTTPS 443 连接提供固定可信服务地址备用路径；HTTP URI 和 Host 保持域名。两条连接都执行系统 CA、证书和对应主机名校验，没有关闭证书检查。其他域名、HTTP、非默认端口和代理不套用此备用连接。
- 仅重试发送 HTTP 之前的连接建立。不会在提交工单/上传之后自动重放业务写入。
- 原生登录继续使用开源 AppAuth。固定 discovery/token TLS 中继保留 canonical issuer、域名浏览器授权地址、nonce 和 PKCE 校验；旧 IP issuer 的已存会话保持原刷新/退出地址。服务器仅将固定 token 路径转发至现有 Keycloak，没有新增账户系统。
- 账户会话管理按原令牌 issuer 选择端点，兼容已保存的旧会话。
- 账户、密码、团队、权限、数据均未修改。

## 股票入口

大字版工作台保留上方4个主入口和完整2×4业务方块。“在线股票”改为下方等宽长条，使用相同面板、圆角、图标底色和8 px间距。点击仍直接打开 WhatIfIBought 原站。360/390/412 px、中英大字截图及对齐断言通过。

## 验证

- 642项 Flutter 全量测试通过；新增连接重试范围、取消、失败、代理、原生 discovery 和旧会话回归测试。
- 提升恢复包版本号后，31项相关测试再次通过；静态分析无问题。
- 本机 Chromium 完成真实团队账号登录和原生 URI 回调，Java HttpsURLConnection 执行 discovery 与 PKCE 令牌交换；额外校验令牌签名、issuer、有效期、audience 和 nonce。
- 同一本机 Dart 客户端读取默认 checkcheck 团队：12名成员、34个任务、11个模板、20条记录、33条通知；读取账户会话、刷新令牌、演示账号及其旧 issuer 会话成功。
- 两种 ABI 的8104/32补丁通过本机 Dart 网络完整下载、Ed25519验签、大小及SHA-256校验；公共配置签名也通过。
- 当前没有连接Android设备；这些证据不代替实际手机的安装、冷启动、原生返回和WebView验收。

## 恢复方式

8104基座已发布序号32修复补丁，546项冻结的原生/资源/引擎文件完全一致。

域名连接已经失败的内容31可能无法下载修复，因此另提供1.1.69+8105完整正式包，内容版本32。必须使用提高versionCode的新基座：上游加载器会拒绝并移除targetVersionCode=8104的旧补丁，避免相同版本覆盖安装后仍加载故障代码。沿用正式签名和包名，覆盖升级保留应用数据，不卸载、不清除数据。

后续8105更新使用独立基座指纹；未改变或轮换APK签名和OTA私钥。证据见 `acceptance/connection143-batch/`。

## 服务端维护

- 中继公开文档：`/srv/linesight/identity/discovery.json`，来自现有 canonical realm discovery，仅替换token_endpoint为固定TLS中继。issuer、authorization_endpoint和end_session_endpoint仍为域名。
- 路由参考 `deploy/sso/native-identity-relay.caddy`，只并入现有IP HTTPS站点，不能覆盖整个实时Caddy配置。
- 此次Caddy修改前备份：`/var/backups/linesight/connection143/Caddyfile`；同目录receipt.json保存变更哈希。配置验证后平滑reload，既有股票、网站、注册关闭及API规则保留。

## 最终发布记录

- 官网稳定下载：https://99ai.pronhubcn.com/linesight/downloads/LineSight-Android.apk
- 正式文件：LineSight-1.1.69-8105-content32-production.apk
- APK SHA-256：edf20a51aac9689bb3a187a4d75310be2b0497730c1d201c107f5cefc8463ba8
- 正式证书 SHA-256：2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2（未变）
- 官网文件已从本机实际Dart网络完整下载，SHA-256与已签名本地包一致。原8103和新8105暂无补丁均返回204；8104双架构返回32。注册410，匿名股票数据302到统一登录，4项现网服务active。
- 门户部署备份：/var/backups/linesight/portal-downloads/20261025T043504Z；原下载兼容规则保留。
