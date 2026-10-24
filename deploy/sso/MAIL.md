# 密码找回邮件

身份认证和密码重置使用 Keycloak 26.8.1 官方流程。公开注册保持关闭，App、API 和身份 issuer 地址不变。

## 正式发信

2026-10-24 已接入现有自托管 Postfix 3.5.8，经 `smtp.163.com:465` 认证中继发送。发件人为 `LineSight <kkk456miao@163.com>`，不冒用自有域名地址。163 中继属于外部邮件服务，Keycloak、Postfix、OpenDKIM、Mailpit 仍由我们自托管。

阿里云[轻量应用服务器限制](https://help.aliyun.com/zh/simple-application-server/product-overview/limits)明确禁止出站 25 发信，建议使用 465。控制台入站放行 25 无法解除该限制。SMTP465 的 TLS 证书及主机名校验已启用，SASL 使用发行版 cyrus-sasl-plain 模块。

`tool/configure_smtp_relay_remote.py` 从 SSH 标准输入读取本机私有配置，不将授权码放入命令行或公开报告。脚本先验证认证并检查空队列，备份配置再切换，校验失败恢复配置。授权码及 Postfix 哈希表以 0600 保存在服务器，已列入加密异机备份。更换授权码后重新执行配置并验证。

正式 realm 已启用 SMTP 和找回密码，官方 SMTP 测试通过；管理员临时测试邮箱已恢复原值。用户已确认实际收到连接测试邮件。正式 realm 一次性账号已通过真实重置邮件收取、设置新密码、旧密码拒绝、新密码 PKCE 登录、动作链接重放拒绝，并已删除测试账号。验收证据在 `docs/product/linesight/acceptance/mail57-batch/`。现有团队账号密码未更改。找回密码要求对应账号已配置本人可访问的邮箱；测试邮箱不会批量替换成员邮箱。

## 隔离测试环境

[Mailpit](https://github.com/axllent/mailpit) v1.32.0（MIT）用于封闭测试。UI/API 仅监听 `127.0.0.1:8025`，SMTP 绑定 `10.89.0.1:1025`，内存上限 96MiB、最多 50 封。Postfix 只监听 `127.0.0.1:2525` 及 `10.89.0.1:2525`，允许本机和当前 Keycloak 容器 `10.89.0.4/32` 转发，无公网 SMTP 监听。容器 IP 变更后需核对白名单。

`example.invalid` 专用传输表继续路由到 Mailpit，防止一次性测试邮件外发。测试 realm `linesight-mail-validation` 禁止注册。`tool/verify_mail_recovery.py` 已通过官方邮件重置、旧密码拒绝、新密码 PKCE 登录及动作链接重放拒绝。`tool/verify_production_mail_recovery.py` 使用正式 realm 的一次性账号验证真实邮件重置，只按本次测试范围读取邮件，动作链接和密码不进入报告，结束后删除账号。

私有查看邮件：

```powershell
ssh -N -L 127.0.0.1:18025:127.0.0.1:8025 -i ~/.ssh/linesight-ali-baot.pem root@47.111.81.94
```

打开 `http://127.0.0.1:18025`。邮件正文及重置链接属于凭据，禁止公开或纳入交付证据。

## 域名与恢复

`99ai.pronhubcn.com`、`mail.99ai.pronhubcn.com` 已解析至生产服务器，HTTPS 证书验证通过。官网为 `https://99ai.pronhubcn.com/` 和 `/linesight/`。SPF、DKIM、DMARC 已发布且与私钥匹配；这是未来自有域名直发的准备，不表示当前 163 From 使用自有域名认证。OpenDKIM 2048 位私钥保存在 `/etc/opendkim/keys/99ai.pronhubcn.com/`，已通过加密副本派生匹配公钥。

邮件配置、DKIM 私钥和 SMTP 授权配置共 13 项部署文件已加入 AES-256-GCM 异机备份，哈希验证通过；不输出明文密钥或数据库。第二台主机完整邮件服务恢复启动仍待验收。恢复时需安装同版软件和 SASL 模块，核对 CA 证书路径、私有监听、容器白名单及传输表，先 Mailpit 验证再开正式投递。
