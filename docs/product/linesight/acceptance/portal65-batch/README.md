# 官网当前交付包发布

2026-10-24，官网 `/` 与 `/linesight/` 从 1.1.20 更新为 **1.1.54+8078 内容版本 4**。

- 首次安装下载 production；旧体验版升级下载 preview。历史 1.1.20 与 preview 使用相同签名，避免跨签名覆盖失败。
- 老版本 URL 302 到 `LineSight-legacy-upgrade.apk`，不覆盖历史 APK；新正式版有 `LineSight-Android.apk` 稳定别名。
- 下载说明改为「我的」统一登录，去除创建本机管理员及独立团队登录指引。
- 「开始使用」图使用 startup64 原生首启验收截图。其余历史截图保留；没有把历史图标成当前版本。
- 上传前逐包核对 delivery.json 的哈希与大小；远端暂存再次校验、并发修改保护、备份、Caddy validate/reload 及失败恢复。

`deployment.json` 保存远端备份位置及发布文件哈希。`public-https.json` 是**服务器侧**使用公共域名和受信任 HTTPS 的完整下载核对：主页、脚本、图片、两个 APK、根路径及 `/linesight/` 旧链接全部通过；不是独立外网客户端验收。

本机 Python 直接访问及经本机 HTTP 代理访问均遇到 TLS EOF，因此未记录本机公网下载通过。未进行浏览器布局验收；JavaScript 语法检查通过。本次仅更新网站及发布工具，未改动 App、账号、登录 issuer 或注册配置。
