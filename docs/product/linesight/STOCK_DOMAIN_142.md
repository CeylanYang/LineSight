# WhatIfIBought 原版界面与域名认证

> 历史记录：Batch142 误选了同名项目 `devinjudson/WhatIfIBought`。
> 用户截图对应的是 `mamawai/wtfibought`，本页的“原版”仅指当时误选的项目，
> 不能作为用户所需项目已交付的证据。更正部署见 `WTFIBOUGHT_144.md`。

2026-10-25，按用户要求恢复原项目桌面/移动界面。上游为
https://github.com/devinjudson/WhatIfIBought ，固定提交
b79f3013cfeb5412508f8d79a2eb31242bc730da。

## 已完成

- 恢复上游首页、Outfit 字体、CSS、投资表单、图表及原始数据回退逻辑；这些文件逐字节核对上游。只保留路径部署、Next 15 参数兼容及构建依赖调整。没有行情服务密钥，数据沿用原项目自带样例。
- 原版服务部署于服务器，systemd 管理、端口仅回环开放。OAuth2 Proxy 7.15.5 官方发布包经 SHA-256 核对，作为独立网关接入现有 Keycloak；没有复制或修改用户密码，没有另建用户库。
- 原 `lsuser01` 账号通过网页实际完成登录、回调、填写表单、回测结果及图表；390/1440 px 无横向溢出。股票登录后访问 `/login` 共用 Keycloak 浏览器会话。
- 大字版工作台新增“在线股票”；特供版股票按钮直接进入原项目，取消经过 Flutter 自制回测页面的中转。
- 新登录与 API 默认地址使用域名。旧 IP issuer 保留兼容，仅允许显式配置的同一 realm 别名；签名、audience、azp、有效期及实时 introspection 校验保持。别名映射保留原账户和团队，避免新建同名身份。
- 旧令牌的刷新/退出保留其签发端点，仅限两个已部署可信地址；任意 JWT 地址不会成为凭据请求目标。原生 PKCE 的域名/旧地址、同一身份、同一团队管理员角色、演示账号及刷新均通过服务器 HTTPS 验证。没有修改密码。
- Keycloak 公开注册关闭；网页没有注册入口，`/register`、旧 API 注册路径返回 410；匿名股票数据请求必须登录。
- 新增认证网关私密配置在本机受限目录 `LineSight-private/whatif-sso-v1` 保存匹配恢复副本，未进入源码或官网。
- 轮换密钥后的公共运行配置重新签发为 revision 3，业务内容不变，新签名与 App v2 信任锚匹配。

## 地址

| 用途 | 地址 |
|---|---|
| 官网 | https://99ai.pronhubcn.com/linesight/ |
| 在线股票 | https://99ai.pronhubcn.com/linesight/whatif |
| 登录/账号 | https://99ai.pronhubcn.com/login |
| OIDC issuer | https://99ai.pronhubcn.com/sso/realms/linesight |
| API | https://99ai.pronhubcn.com/api/v1/ |

复用已有域名，不需要新 DNS 记录。注册仍关闭。

## 验证与交付

634 项 Flutter 完整测试、119 项后端完整测试通过；静态分析无问题。
已发布1.1.68+8104内容版本31完整正式包，以及该基座的序号31 OTA补丁。
546项原生/资源/引擎指纹不变，两个ABI均经服务器HTTPS下载验签及SHA-256核对；旧8103清单仍为204。官网安装包完整下载哈希一致。
证据目录 `acceptance/stock142-batch` 包含上游一致性、浏览器截图、登录/身份/刷新验证及发布记录；具体APK和哈希见同目录delivery.json。

部署前备份 `/var/backups/linesight/stock142/20261025T032448Z`；33 张业务表、全部原行内容在切换时一致。现有身份库、团队和密码保留。源码部署过程及恢复位置见 `third_party/whatifibought/README.md`。

本轮浏览器/PKCE/组件验证没有替代 Android 真机 WebView 和原生 AppAuth 回调验收。
