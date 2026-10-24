# 自托管密码找回邮件

密码重置使用现有Keycloak 26.8.1官方流程，SMTP验收使用[Mailpit](https://github.com/axllent/mailpit) v1.32.0（MIT）。不实现自制重置令牌、验证码或邮件协议。

当前域名`99ai.pronhubcn.com`及`mail.99ai.pronhubcn.com`已解析至生产服务器，两者`/health`已通过HTTPS证书校验。新增Caddy站点只提供健康响应，未迁移App API、身份issuer或OAuth回调。现阶段是内部邮件测试环境，不能向真实邮箱投递。正式realm的SMTP保持原状，公开注册保持关闭。测试realm `linesight-mail-validation`同样关闭注册，测试用户用后删除。

Mailpit官方Linux amd64发布包安装到`/opt/linesight-mailpit/mailpit`，systemd单元见`linesight-mailpit.service`。内存上限96MiB、CPU配额25%，数据库私有目录`/var/lib/linesight-mailpit`，最多保留50封。HTTP界面/API仅监听`127.0.0.1:8025`；SMTP只绑定现有身份容器网关`10.89.0.1:1025`，不开放公网SMTP或邮箱查看入口。网络重建后必须核对网关并同步修改绑定及测试realm配置。

私有查看：

```powershell
ssh -N -L 127.0.0.1:18025:127.0.0.1:8025 -i ~/.ssh/linesight-ali-baot.pem root@47.111.81.94
```

随后打开`http://127.0.0.1:18025`。找回邮件含登录凭证，禁止公开端口、保存邮件正文或动作链接到交付证据。`tool/verify_mail_recovery.py`建立独立隧道并使用一次性测试账号，验证正式Keycloak邮件流程，公开报告只记录布尔结果。

2026-10-24已完成隔离账号实际重置邮件收取、设置新密码、旧密码拒绝、新密码PKCE登录及动作链接重放拒绝，测试账号已删除。证据：`docs/product/linesight/acceptance/operations55-batch/mail-recovery.json`。生产realm的SMTP、用户密码及关闭注册配置保持原状。

服务器实际外连探针：外部SMTP的25端口连接失败，465/587成功。直接投递需要先确认云平台出站25端口限制并申请开放；若无法开放，则需要SMTP中继，不能仅靠域名解析解决。

正式投递前仍需要：可管理DNS的域名、实际收件邮箱、发信出口；部署Postfix或Stalwart等开源投递服务并配置TLS、SPF、DKIM、DMARC及适用的PTR。确认实际邮箱收到邮件并完成重置后，才在正式realm启用SMTP。Mailpit收件成功不能证明真实邮件投递成功。

## 域名邮件暂存链路

已安装发行版仓库Postfix 3.5.8及OpenDKIM 2.11.0，部署脚本`tool/configure_postfix_remote.py`。Postfix只监听`127.0.0.1:2525`及身份容器网关`10.89.0.1:2525`，允许本机及当前Keycloak容器`10.89.0.4/32`转发，未开放公网SMTP。OpenDKIM只监听`127.0.0.1:8891`；2048位RSA私钥在`/etc/opendkim/keys/99ai.pronhubcn.com/`，opendkim专属权限，不能进入公开交付。

当前relayhost固定为私有Mailpit：Keycloak测试realm → Postfix → OpenDKIM签名 → Mailpit。完整找回测试已通过，捕获邮件存在`d=99ai.pronhubcn.com`签名；尚未用公共DNS验证签名，也尚未验证外部送达。生产realm未启用该链路。

客户待添加的三条TXT（SPF、DKIM、DMARC）在`D:/ENT207/deliverables/LineSight-mail-domain/DNSHE-TXT记录.txt`，只含公钥及公开解析信息。无需MX，当前不提供收件邮箱。DKIM selector为`linesight2026`，DMARC先使用`p=none`观测。

出站25端口开放、TXT生效及PTR条件核实后，方可移除Mailpit中继并测试指定真实收件邮箱。更改中继前先检查队列，避免测试邮件意外外发。身份容器IP变化需同步白名单；默认失败关闭转发。邮件配置、DKIM密钥的完整异机备份与恢复验证还需补入运维流程。
