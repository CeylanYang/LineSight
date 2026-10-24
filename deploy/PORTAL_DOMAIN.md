# LineSight 官网域名

正式访问入口：`https://99ai.pronhubcn.com/`。兼容入口：`https://99ai.pronhubcn.com/linesight/`。原IP路径保留。

DNSHE使用托管模式，主机`@`的A记录为`47.111.81.94`，TTL300秒。DNS只指向服务器，URL路径由服务器Caddy处理，解析记录不能填写`/linesight/`。

Caddy将主域名根路径和`/linesight/*`映射到既有`/srv/boji-portal`，HTTPS证书自动管理。`tool/publish_portal_domain.py`为服务器端配置脚本，替换专用标记区，变更前备份，先验证配置再热重载；验证或重载失败恢复原配置。未变更官网文件、App API地址、Keycloak issuer或AppAuth回调。

实际验证：主域名首页与原IP路径字节一致，兼容路径一致；31个脚本、样式、图片/音频和APK链接HEAD全部200。证据：`docs/product/linesight/acceptance/operations55-batch/portal-domain-verification.json`。浏览器未执行完整交互验收。
