# 云端备份与恢复

生产业务目录 `/var/lib/linesight`；身份容器 `linesight-identity_postgres_1`。
备份目录 `/var/backups/linesight/complete/<UTC时间>`，仅 root 可读。

## 已部署的日常备份

`linesight-cloud-backup.timer` 每天服务器时间03:20起随机延迟最多10分钟运行，停机错过后补执行。

```sh
systemctl list-timers linesight-cloud-backup.timer
systemctl show linesight-cloud-backup.service -p Result -p ExecMainStatus
journalctl -u linesight-cloud-backup.service --since yesterday
```

单次在线备份：

```sh
/opt/linesight/venv/bin/python /opt/linesight-identity/api-cutover/rehearse_cloud_restore.py --backup-only
```

每个成功备份包含SQLite、该快照引用的原图/边缘图、后端源码、业务环境配置、身份部署配置、PostgreSQL自定义格式转储、realm初始化文件、NFC身份插件JAR、恢复脚本及私有逐表/逐文件清单。业务库使用在线一致性快照；身份库的转储及源数据指纹共享同一PostgreSQL导出快照。两个系统分别取快照，没有分布式原子快照保证。

日常备份不清理历史。2026-10-24已部署本机任务`LineSight-Encrypted-Offhost-Backup`：用户登录期间每天04:15及登录时运行；错过后补跑，失败每15分钟重试最多两次。执行`tool/offhost_backup.py`创建新的服务端快照、使用独立随机密钥AES-256-GCM加密、经SSH复制到本机私有目录，并验证认证标签、全部文件指纹、业务库逐表行指纹、外键及身份库转储指纹。已分别完成直接运行与Windows定时任务实际运行，任务退出码0。

本机位置`~/LineSight-private/cloud-backups/`，用户及SYSTEM ACL；每个恢复点的密钥在`keys/<时间戳>.bin`，服务器临时导出密钥用后删除。最近成功状态`last-success.json`，失败不会覆盖；任务状态通过`Get-ScheduledTaskInfo -TaskName LineSight-Encrypted-Offhost-Backup`查看。重装任务：`tool/install_offhost_backup.ps1`。本机未登录或关机时不能执行，服务器原每日备份继续独立运行。

当前保留全部恢复点、不自动删除；有期限的清理策略、容量告警、签名/备份密钥异地托管及另一台服务器恢复启动仍待完成。凭据、私有清单、原始数据库和图片不得放入客户安装包或公开证据目录。

## 隔离恢复演练

```sh
/opt/linesight/venv/bin/python /opt/linesight-identity/api-cutover/rehearse_cloud_restore.py
```

命令先新建备份，将SQLite和图片复制到其`restored`子目录，并将身份转储恢复到唯一的`linesight_restore_*`临时数据库。业务库全表逐行哈希、完整性、外键、图片字节指纹和身份库全表行指纹必须一致；身份临时库在校验后删除。API探针只允许访问专用`restored`目录，实际Django数据库路径必须匹配；随后仅在副本新增两个测试账号，验证读取、viewer禁止写、跨团队404、匿名401和受权图片读取。

上述基础API探针注入身份。完整身份演练另运行以下命令，必须选择新的成功备份，不覆盖以前的演练目录：

```sh
/opt/linesight/venv/bin/python /opt/linesight-identity/api-cutover/rehearse_restored_identity.py \
  /var/backups/linesight/complete/<UTC时间> \
  --demo-config /root/linesight-restore-private/demo-build.json
```

完整演练使用独立临时数据库、原Keycloak镜像和备份NFC插件，容器仅绑定127.0.0.1:18081，内存上限512MiB。主机回环HTTP用于探针，issuer保持正式HTTPS值，所有跳转被限制在副本。先核对31张业务表、101张身份表及28张图片，再验证原演示账号密码登录、仅在副本新增的普通账号PKCE登录、真实JWT签名及introspection、刷新轮换、登出失效、viewer写入403、团队外及移除成员读取404、授权图片字节一致。结束后删除临时容器/环境文件/身份库，不修改生产用户和会话。NFC插件加载已验，但本次未执行完整NFC刷卡登录。

公开`report.json`、`identity-rehearsal-report.json`及运维验证结果可以交付；`private-manifest.json`及数据库转储保持私有。

## 加密异机副本与取回

导出工具为仓库`tool/export_cloud_backup.py`，依赖同目录两个恢复脚本及Python cryptography。密钥为本机生成的32字节随机文件，保存在受当前用户与SYSTEM ACL保护的`LineSight-private/cloud-backups/keys/`，不打印、不提交。仅临时上传至服务器`/root/linesight-restore-private/export-key.bin`并设0600。导出命令执行后会删除该临时密钥。

```sh
python export_cloud_backup.py encrypt /var/backups/linesight/complete/<UTC时间> \
  --key-file /root/linesight-restore-private/export-key.bin
```

将`portable-backup.lsbk`通过SSH复制到本机私有目录，密钥单独存放。运行以下命令验证GCM认证、所有归档文件指纹、业务库逐表行指纹和外键，以及身份转储、图片和NFC插件指纹。公开报告只包含计数和哈希。

```sh
python export_cloud_backup.py verify /private/portable-backup.lsbk \
  --key-file /private/backup-key.bin --report /public/off-host-verification.json
```

整机重建时安装匹配的PostgreSQL17、Keycloak26.8.1镜像和Python依赖，恢复工具及加密文件、密钥经私有通道放到新主机。以root解密到**尚不存在**的标准时间戳备份目录：

```sh
python export_cloud_backup.py decrypt /private/portable-backup.lsbk \
  --key-file /private/backup-key.bin \
  --output /var/backups/linesight/complete/<UTC时间>
```

该命令先验证全部内容，拒绝覆盖、路径穿越、链接和重复文件，再以目录0700/文件0600恢复。解密不启动服务或切换生产。随后按下面顺序恢复，先对恢复点运行完整身份演练。当前工具内存解密限256MiB加密文件；超过后须实现流式校验再导出。已验证异机副本完整性及服务器隔离解包，尚未在另一台主机启动PostgreSQL/Keycloak，也未演练生产切换。

## 生产恢复和回滚顺序

以下是维护窗口的执行顺序，本次演练没有执行生产切换。

1. 选定包含成功`report.json`的恢复点，核对其中三个备份文件的SHA-256。先再次执行`--backup-only`保留切换前状态；暂停备份timer及业务写入，记录切换前源码版本、数据目录和身份配置。
2. 停止`linesight.service`及Keycloak容器，保留PostgreSQL容器运行。将原业务数据目录改名为带时间戳的回滚目录，原样保留SQLite及其WAL/SHM；另建业务目录并放入备份SQLite和media，设置所属用户`linesight`。不要把旧WAL覆盖到恢复数据库。
3. 从备份恢复同一版本后端源码及业务环境，先在隔离目录运行对应版本迁移并核对所有原始行。不得用旧源码打开已经向前迁移且不兼容的数据库。
4. 将`identity.dump`恢复到新建的专用恢复数据库，使用`pg_restore --exit-on-error --no-owner --no-acl`，保留原`keycloak`数据库。恢复同一版本的`realm/`、`providers/`及匹配镜像，核对NFC插件指纹。将Keycloak的`KC_DB_URL`持久改为新数据库，保留切换前compose配置。PostgreSQL当前集群账号密码与Keycloak数据库连接凭据必须一致；旧环境文件不能自动替换已经轮换的数据库密码。
5. 启动身份服务和业务服务，检查公开发现文档、业务健康、真实普通/演示账号登录、刷新/登出、团队隔离、历史任务/轮次、图片下载和报告。身份库恢复可能带回旧会话状态，恢复上线前需在Keycloak撤销既有会话，再验证旧令牌拒绝。验收成功后恢复timer。
6. 若任一步失败，停止业务及Keycloak，将compose连接改回原身份库、业务目录改回切换前目录、恢复匹配的源码/环境，再启动并做同样健康及登录校验。原数据库和回滚目录在确认完成前保留，不删除或覆盖。

实际生产恢复需由维护窗口执行并记录；本次结果证明隔离恢复后真实OIDC登录及API权限，不代表已经演练生产切换。
