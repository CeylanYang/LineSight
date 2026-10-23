# 最新云端开发交接

2026-10-23。总目标仍为逐项完成原产品计划并截图，未完成，不得标记总目标完成。

工作区`C:/Users/29668/LineSight-workspaces/product-plan`，分支`feature/product-plan`。基线`8b7147d`，权限基础`7572f92`，新代码见后续云身份/任务提交。Excel为主表56项，0项已验收；`update_cloud_backlog.mjs`导入原表更新，CSV仅镜像。

## 实际已上线

- Keycloak26.8.1 + PostgreSQL17，以Podman Compose/systemd运行。issuer为`https://47.111.81.94/sso/realms/linesight`，Caddy转发loopback8081。
- 普通客户端使用授权码+PKCE S256，无密码授权；共享演示客户端单独配置，只访问独立演示团队。
- API验证RS256/issuer/audience/azp/exp/iat/sub并每请求introspection；退出即时失效，身份服务故障503；旧客户注册/密码登录410。
- 5个原账户保留Argon2原密码并绑定原Django用户；不按登录用户声称的username/email关联。临时账号真实导入登录验证通过。
- 部署备份源码/环境/SQLite，核对原23表全部旧行不变。脚本曾遇系统旧SQLite、健康检查Host错误，均自动回滚；修正后成功上线。中断导入恢复通过可信密码表示精确比对，不靠同名授权。
- migration0003上线：任务version、JobMutation幂等回执、事件job/version/details。云端状态/检验/异常处理要求version和Idempotency-Key，事务CAS，409带当前任务；不能PATCH绕过异常关闭/复检，授权关闭需owner+处置+依据，处理结果不可覆盖，复检新增轮次，关闭不可重开。
- 真实HTTPS并发验证：一个成功一个409；重复检验/处理幂等、双轮次、不覆盖、事件版本均通过。证据在`acceptance/sso/live-workflow-verification.json`。

## Flutter实际变化

- main使用CloudShell：普通与团队统一云身份，登录为二级路由；访客不读保护本机数据；工作区切换/资料/只读成员/托管改密/退出。AppAuth+secure_storage，会话恢复与本机初始化在无反光粒子动画期间并行。
- 新云任务搜索/状态筛选/新建/详情概览质检异常历史/打印送检/登记检验/异常处理/复检；冲突保留说明并要求返回刷新。二态检验仍非完整QC清单。
- 请求key已添加固定前缀，避免旧uid偶发15字符被服务端拒绝；登录过期隐藏任务详情/命令表单/成员缓存，新增UI回归测试。
- 最新Flutter全量113项通过（含过期详情隐私门禁、冲突保留输入、双语窄屏）；后端30项通过；静态检查通过。真实云API与两条Android旅程亦通过。
- Android云登录旅程再次通过（构建8027），7张真实PNG已更新；成员页已使用客户显示名称，旧内部映射名截图已替换。
- Android完整任务旅程首次因系统键盘改变坐标导致点击未命中，加入收起键盘/等待后复测通过（41秒），新增9张真实PNG（08–16），覆盖新建/状态/异常/处理/双轮次/历史/筛选。日志`.artifact-work/sso/android-workflow-journey.log`。

## 位置/命令

- 部署结构与恢复：`deploy/sso/README.md`。验证脚本：`verify_keycloak.py`、`verify_legacy_password_import.py`、`verify_cloud_api.py`、`verify_live_workflow.py`。
- API远端`/opt/linesight/backend`，venv`/opt/linesight/venv`；环境`/etc/linesight/linesight.env`；DB`/var/lib/linesight/linesight.sqlite3`。
- 最近备份`/var/backups/linesight/identity/api-20261023T100339Z`，原24表旧行全保留；后续部署脚本仍按同样机制备份和核验。
- staging`/opt/linesight-identity/api-cutover`。构建私密输入`.artifact-work/sso/demo-build.json`，不得打印/提交；仅演示身份可编入App，无基础设施或管理员密钥。
- Gradle用户代理127.0.0.1:7897目前未运行，显式传`-Dhttp.proxyHost= -Dhttps.proxyHost=`及`-I ../tool/gradle_mirrors.init.gradle`；显式Gradle还需私下编码dart-defines传入。
- emulator-5554已测试构建8026/8027；正常main入口测试包版本1.1.21+8030正在构建。后续更新不能降级，不卸载/不清数据。集成测试APK不能交付为正常客户APK；正式main配置须在release构建前重新生成。
- SSH沿用现有`~/.ssh/linesight-ali-baot.pem`，不输出凭证。

## 继续顺序

1. 完成Android任务旅程，替换成员页截图，记录构建与日志；生成正常main入口测试APK。当前Android release配置仍debug签名，REL-01未完成。
2. 统一身份下团队创建/加入/邀请/改权移除/同步状态及真实Android角色撤权回归。
3. DAT-02/05、QC模板三态清单、工件数量/批次/SN、证据绑定检验、异常分类/责任人/前后图；当前不可当作完整QC验收。
4. 工作台趋势/我的待办/洞察、按工件口径报告CSV/PDF、通知扫码、离线草稿/上传/冲突恢复。
5. SMTP重置邮件，身份库定时备份与恢复演练，正式签名无损升级、诊断、双语全流程及客户文案审阅。
6. 两台真实Android及至少10名外部用户尚缺，不伪造、不标记完成；其他开发继续。

不要因SSO与基本任务链通过而缩小总目标或将未完成依赖标记已验收。原文51项+追加5项均保留固定ID逐项推进。
