# NFC 与 Keycloak 集成

Android 通过开源 [nfc_manager](https://github.com/okadan/flutter-nfc-manager) 读取卡片。NFC-A/B/F/V、MIFARE Classic/Ultralight、ISO-DEP 统一使用 Android Tag 标识；已有 LineSight NDEF 标记优先使用32字节随机标记。用户可主动初始化已格式化、可写且空白的 NDEF 卡；不覆盖已有内容，不改成只读。

UID及普通NDEF内容可复制，因此不能单独充当账户密码。本实现将卡片、账户及本机Ed25519密钥共同绑定：密钥种子由Android加密安全存储保护，服务端只保留公钥与卡片标识的HMAC。换手机需要先使用账户登录后绑定，不提供跨设备的UID单因子登录。ISO-DEP只表示可读取卡片标识，尚未实现特定型号的DESFire安全消息、APDU挑战或厂商密钥体系，也未声称所有实体卡兼容。

绑定要求5分钟内的原生账户认证，NFC会话不能自行追加新的卡片。服务端生成60秒挑战，Ed25519签名覆盖操作、随机挑战、绑定ID、卡片摘要和刷新令牌摘要。挑战消费采用数据库条件更新，一次性使用。

通过签名验证后，后台向独立保密客户端 `linesight-nfc` 发送30秒服务端断言。`NfcTicketAuthenticator` 使用官方Keycloak Authenticator SPI验证HMAC、客户端、有效期、账户启用状态及一次性断言，再由Keycloak签发标准访问／刷新令牌。原生账号仍使用AppAuth PKCE，未给普通客户端开启密码授权，也未在App嵌入NFC客户端密钥或用户密码。

刷新需再次完成设备签名挑战，服务端记录刷新摘要并轮换，令牌不会作为明文写入业务数据库。客户端安全存储保留令牌及对应绑定ID。所有业务API除JWT与实时Keycloak introspection外，还校验NFC会话、账户和卡片绑定；解绑立即阻止API访问及后续刷新。指定NFC会话退出调用Keycloak官方logout并撤销本地会话记录，不影响密码会话。

`tool/build_nfc_provider.py` 只使用本地JDK编译小型SPI，没有虚拟机或容器运行时。服务器已有Keycloak容器挂载JAR，部署前执行完整备份，配置失败恢复原runtime配置。`tool/deploy_nfc_identity.py`只在云端执行，密钥写入受限权限环境文件，禁止提交或输出密钥。

实体手机、实体卡、不同厂商读卡器和后台／前台切换仍需真机验证。当前云端证据使用生成的卡片摘要和设备密钥，证明服务端认证与令牌链路，不构成物理读卡验收。
