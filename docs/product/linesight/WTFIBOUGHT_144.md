# What If I Bought 项目更正

2026-10-25，已将股票站点从误选的 `devinjudson/WhatIfIBought` 更换为用户截图
对应的 [mamawai/wtfibought](https://github.com/mamawai/wtfibought)，固定提交
`d99fd9bae3564a2630880a3a8f52fcd0dfee7bdb`，MIT 许可证随部署保留。

入口仍为 https://99ai.pronhubcn.com/linesight/whatif/ 。大字版和特供版已有入口
继续访问此地址，无需发布新 APK 或 OTA。Batch143 的连接修复及正式包保持不变。

## 已交付

- 保留原项目电脑/手机界面、导航、首页资产区、月度盈亏、行情、持仓、竞技场、
  配置、策略与回测页面。9 个核心页面/组件/CSS 文件按 Git 的 LF 行尾核对上游一致；
  布局、配色和业务逻辑没有重新设计。
- 使用原项目 Java 25 feed/sim/agent 后端、独立 PostgreSQL `wiib` 数据库与角色
  （39 张表）、独立 Redis。三个 JVM 和网关均由 systemd 管理，端口仅回环开放。
  原 LineSight 和身份数据库未迁移或重置。误选项目的 Node 服务已停止，文件保留用于回退。
- 继续使用现有 Keycloak + OAuth2 Proxy、原 LineSight 账号密码及 PKCE 回调。
  补齐 Keycloak 26 标准 `basic` scope 和 `wiib` access-token audience。
  Spring Security 的 JWT 库校验签名、issuer、有效期、audience、azp；以不可变 `sub`
  关联原项目资料，不按同名账户合并。没有复制或修改用户密码。
- `lsuser01` 对应原项目管理员 id 1；普通用户和策略机器人 id 从 100 起，避免误获
  管理权限。SSO 首登建原项目资料及其初始虚拟资金流水，本地密码字段保持空。
- 关闭原项目本地管理员直登、密码登录、LinuxDo 回调、注册和登录模式接口（410），
  网页登录由现有 SSO 接管；原 realm 公开注册继续关闭。
- 完成子路径下静态资源、路由刷新、原始 K 线、SSE、SockJS/WebSocket、PWA 适配。
  内部静态服务接受网关转发的公共 Host。SSO 失败最多自动重试一次，避免反复跳转。
- 现货使用 Binance 官方公共数据 REST/WS 地址；实测 10 只代币化美股均有实时价，
  NVDA 的 10 根真实 K 线读取成功，没有用假数据替代行情。

## 验证

证据目录：`acceptance/wtf144-batch/`。

- 前端 TypeScript/Vite 生产构建和后端 Maven reactor 构建成功。Maven 使用
  `-DskipTests`，编译了上游测试源码，但没有声称运行完整上游单元测试。
- 浏览器验证通过：现有管理员登录、普通账户身份隔离、会话复用、刷新保留身份、
  退出后重新要求登录、公开注册/本地直登关闭、伪造上游身份头拒绝。
- 股票、Crypto、持仓、竞技场、模型配置、策略、回测、我的，共 8 个页面可进入并刷新。
  1440/390 px 无横向溢出；带触摸的手机上下文验证持仓、我的、配置、首页底栏。
- 10 只股票实时价、真实 K 线、STOMP 连接、资料偏好保存及恢复通过。
  三个服务带原生会话的依赖健康检查均为 UP；浏览器无页面异常或意外 HTTP 错误。
- 末次手机首页测试定位器按 BrowserRouter 实际无尾斜杠的根链接修正后，单独重跑
  失败阶段通过；其余已通过检查没有重复执行。见 `verification.json`。
- 初次划转验证发现并遵循原项目 1% 手续费；已返还测试存入的游戏钱包余额，产生
  0.02 虚拟手续费，保留原始账本记录。没有操作真实资金或重置账户。
- 此次为网页/服务器验收，没有连接 Android 真机，不替代 App WebView 真机验收。

## 实际限制

- 当前服务器无法连接 Binance 合约及 Polymarket 相关数据源，合约、商品及预测
  部分没有实时数据。现货价格与 K 线已独立验证正常。
- 未配置 LLM、新闻服务及 Testnet 密钥；模型调用与相关外部服务不作为已开通功能。
  原版 BYOK 配置页面可用，配置模型后方可运行 AI。
- Python 3.13 的可选因子挖掘服务尚未部署，其独立页面/API 返回 503。
- 主机约 2 GB 内存，已限制 JVM 堆、连接池和内存，并关闭大户地址采集。
  小团队浏览已验证；未做负载测试，冷启动较慢。

部署脚本、补丁、身份适配器和恢复说明在 `third_party/wtfibought/`。
回退文件在服务器 `/var/backups/linesight/wtf144`；新私密配置在
`/etc/linesight/wiib.env`，本机 `LineSight-private/wtfibought-v1` 保有副本。
APK/OTA 签名密钥未改动。
