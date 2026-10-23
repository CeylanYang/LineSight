# Android 发布签名

`tool/build_signed_delivery.ps1 -Track production` 使用独立 RSA3072 正式证书。正式签名配置缺失时，release 构建失败。`-Track preview` 显式选择与既有预览安装兼容的证书。两条轨道的 applicationId 相同，签名不同。

正式证书 SHA256：`2427e2ea173f5c33ce915b4268c8c78fe4622d774ec8831e7c53d223486ad0b2`。

旧预览证书无法直接升级为正式证书。已有预览安装应继续使用兼容预览轨道，直到具备经过验证的数据迁移方案。不要通过卸载或清数据绕过签名冲突。

`tool/prepare_release_signing.py` 创建或复用私有密钥，核验第二份本地私有备份，并且仅发布证书摘要。私钥、密码和签名属性均位于 Git 忽略目录。异地托管和恢复演练仍待完成。正式签名材料不进入 APK、源码和交付目录。

`-WithAudit` 另外生成同签名的原生存储验收 APK，仅供模拟器验收。它读取目标应用持久文件摘要、SQLite 完整性与行摘要、KeyStore 别名摘要，并按需写入随机升级哨兵。客户 APK 不包含该 instrumentation 或 Flutter IntegrationTestPlugin。验收 APK 不向客户分发。

客户端继续内置服务端地址和独立演示团队的共享演示登录配置，符合用户明确要求。该配置只授予演示团队权限，不包含后端密钥、Keycloak 客户端机密或管理员凭据。原方案 REL-01 中“不携带演示固定凭证”由此要求修订；其余发布条件保留。
