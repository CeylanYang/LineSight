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

每个成功备份包含SQLite、该快照引用的原图/边缘图、后端源码、业务环境配置、身份部署配置、PostgreSQL自定义格式转储、恢复脚本及私有逐表/逐文件清单。业务库使用在线一致性快照；身份库的转储及源数据指纹共享同一PostgreSQL导出快照。两个系统分别取快照，没有分布式原子快照保证。

日常备份不清理历史。当前备份位于同一台云主机；异机/对象存储副本与保留周期尚未配置，不能据此承诺整机丢失后的恢复能力。凭据、私有清单、原始数据库和图片不得放入客户安装包或公开证据目录。

## 隔离恢复演练

```sh
/opt/linesight/venv/bin/python /opt/linesight-identity/api-cutover/rehearse_cloud_restore.py
```

命令先新建备份，将SQLite和图片复制到其`restored`子目录，并将身份转储恢复到唯一的`linesight_restore_*`临时数据库。业务库全表逐行哈希、完整性、外键、图片字节指纹和身份库全表行指纹必须一致；身份临时库在校验后删除。API探针只允许访问专用`restored`目录，实际Django数据库路径必须匹配；随后仅在副本新增两个测试账号，验证读取、viewer禁止写、跨团队404、匿名401和受权图片读取。

API权限探针使用测试客户端注入身份，验证的是恢复后的业务权限，不等于恢复后Keycloak启动和真实OIDC登录。当前演练验证身份库账号、凭据、客户端、签名密钥等表完整恢复，未启动第二个Keycloak。公开`report.json`及运维验证结果可以交付；`private-manifest.json`及数据库转储留在服务器。

## 生产恢复和回滚顺序

以下是维护窗口的执行顺序，本次演练没有执行生产切换。

1. 选定包含成功`report.json`的恢复点，核对其中三个备份文件的SHA-256。先再次执行`--backup-only`保留切换前状态；暂停备份timer及业务写入，记录切换前源码版本、数据目录和身份配置。
2. 停止`linesight.service`及Keycloak容器，保留PostgreSQL容器运行。将原业务数据目录改名为带时间戳的回滚目录，原样保留SQLite及其WAL/SHM；另建业务目录并放入备份SQLite和media，设置所属用户`linesight`。不要把旧WAL覆盖到恢复数据库。
3. 从备份恢复同一版本后端源码及业务环境，先在隔离目录运行对应版本迁移并核对所有原始行。不得用旧源码打开已经向前迁移且不兼容的数据库。
4. 将`identity.dump`恢复到新建的专用恢复数据库，使用`pg_restore --exit-on-error --no-owner --no-acl`，保留原`keycloak`数据库。将Keycloak的`KC_DB_URL`持久改为新数据库，保留切换前compose配置。PostgreSQL当前集群账号密码与Keycloak数据库连接凭据必须一致；旧环境文件不能自动替换已经轮换的数据库密码。
5. 启动身份服务和业务服务，检查公开发现文档、业务健康、真实普通/演示账号登录、刷新/登出、团队隔离、历史任务/轮次、图片下载和报告。身份库恢复可能带回旧会话状态，恢复上线前需在Keycloak撤销既有会话，再验证旧令牌拒绝。验收成功后恢复timer。
6. 若任一步失败，停止业务及Keycloak，将compose连接改回原身份库、业务目录改回切换前目录、恢复匹配的源码/环境，再启动并做同样健康及登录校验。原数据库和回滚目录在确认完成前保留，不删除或覆盖。

实际生产恢复需由维护窗口执行并记录；本次结果只证明隔离恢复，不宣称已经演练生产切换或恢复后真实OIDC登录。
