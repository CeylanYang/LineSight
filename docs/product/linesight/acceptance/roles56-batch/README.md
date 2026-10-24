# 四角色线上权限验收

当前生产API及Keycloak实际HTTPS/PKCE验收，使用4个一次性身份和独立临时团队，没有改动checkcheck团队或其账号。

`live-role-matrix.json`证明：owner/manager/operator/viewer均可读取任务、记录、统计、报表、模板、成员、打印配置及通知；前三种角色可创建任务，viewer创建返回403；manager/operator/viewer邀请成员返回403。manager降权为viewer后原令牌401，重新PKCE登录可读200、写入403；移除后原令牌读取404；最后一位owner离组409。

清理已通过：4个API用户、5个临时工作区及4个Keycloak身份全部删除。证据不含密码、令牌、邀请码或业务记录正文。真实操作产生的安全日志保留。

本批没有验证最终APK全部角色页面、双真机协作、实体NFC/摄像头或10名外部用户；这些验收仍待完成。
