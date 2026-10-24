# 自托管密码找回邮件

密码重置使用现有Keycloak 26.8.1官方流程，SMTP验收使用[Mailpit](https://github.com/axllent/mailpit) v1.32.0（MIT）。不实现自制重置令牌、验证码或邮件协议。

当前无可用域名，部署的是内部邮件测试环境，不能向真实邮箱投递。正式realm的SMTP保持原状，公开注册保持关闭。测试realm `linesight-mail-validation`同样关闭注册，测试用户用后删除。

Mailpit官方Linux amd64发布包安装到`/opt/linesight-mailpit/mailpit`，systemd单元见`linesight-mailpit.service`。内存上限96MiB、CPU配额25%，数据库私有目录`/var/lib/linesight-mailpit`，最多保留50封。HTTP界面/API仅监听`127.0.0.1:8025`；SMTP只绑定现有身份容器网关`10.89.0.1:1025`，不开放公网SMTP或邮箱查看入口。网络重建后必须核对网关并同步修改绑定及测试realm配置。

私有查看：

```powershell
ssh -N -L 127.0.0.1:18025:127.0.0.1:8025 -i ~/.ssh/linesight-ali-baot.pem root@47.111.81.94
```

随后打开`http://127.0.0.1:18025`。找回邮件含登录凭证，禁止公开端口、保存邮件正文或动作链接到交付证据。`tool/verify_mail_recovery.py`建立独立隧道并使用一次性测试账号，验证正式Keycloak邮件流程，公开报告只记录布尔结果。

2026-10-24已完成隔离账号实际重置邮件收取、设置新密码、旧密码拒绝、新密码PKCE登录及动作链接重放拒绝，测试账号已删除。证据：`docs/product/linesight/acceptance/operations55-batch/mail-recovery.json`。生产realm的SMTP、用户密码及关闭注册配置保持原状。

服务器实际外连探针：外部SMTP的25端口连接失败，465/587成功。直接投递需要先确认云平台出站25端口限制并申请开放；若无法开放，则需要SMTP中继，不能仅靠域名解析解决。

正式投递前仍需要：可管理DNS的域名、实际收件邮箱、发信出口；部署Postfix或Stalwart等开源投递服务并配置TLS、SPF、DKIM、DMARC及适用的PTR。确认实际邮箱收到邮件并完成重置后，才在正式realm启用SMTP。Mailpit收件成功不能证明真实邮件投递成功。
