# OTA 启动异常回退与日志保护

2026-10-24，独立新建 `LineSightOtaFaultValidation` API34 x86_64 AVD，首次安装冻结的正式内容 4 APK，保留其他 AVD 与客户数据。

发现 `flutter_patcher.init()` 会包装先前安装的异常过滤器，在调用过滤器之前把原始 `error.toString()` 传入 Android 的 `reportDartBootError`。上游原生 CrashGuard 会将这个字符串写入日志。因此仅验证 App 自己的错误处理器不足以证明插件链路安全。

修复：模块初始化结束后再包一层过滤器，给已安装的模块处理链传入固定来源/类别异常、空堆栈和无上下文的 FlutterErrorDetails。保留上游启动故障报告、阈值、补丁移除、黑名单与首帧观察逻辑。未替换开源加载器或手写回滚算法。

实际验收使用 `tool/fixtures/ota_boot_fault.dart` 构建 AOT 故障入口，包含真实 FlutterPatcher 初始化和本次修复；原生、引擎、资源与冻结交付指纹完全一致。独立同签名 audit APK 通过冻结 R8 类安装本地补丁，分别注入框架 StateError 和根 isolate 未捕获 PlatformException，异常、堆栈、上下文、插件详情中含合成测试标记。**故障包只存在本机与此模拟器，从未上传分发服务器。**

`validation.json` 证明两类故障均：

- 真正加载 AOT 补丁；原生 CrashGuard 收到固定错误类别并触发一次失败熔断。
- 故障 .so 被移除，版本进入 BOOT_CRASH 黑名单；重新应用同一版本/摘要被拒绝。
- 冷启动恢复冻结基础 APK 的工作台导航。
- 对两个故障进程分别检查 47/46 行完整现存日志，未找到原始合成标记；未将原始系统日志存入仓库。

367–368 为首次启动被 Android 系统 Bluetooth keeps stopping 弹窗遮挡、关闭后工作台正常的证据；不是 App 启动卡死。369–372 是两次故障及恢复的截图/XML。首次等待因此超时后使用 `--resume-installed` 继续，核对模拟器安装 APK 哈希与冻结文件一致，未重装或清除数据。

复现：新建同名隔离 AVD（已有时保留数据），运行 `tool/build_ota_boot_fault.ps1`，再运行 `tool/verify_ota_boot_fault.py`；中断后只可显式 `--resume-installed`，检查现有状态。验收 APK 保存在 `.artifact-work/ota67-fault/`，正常构建仍使用 `lib/main.dart`。

这证明 API34 x86_64 的**启动期 Dart 故障**自动回退，不等同于验证原生 SIGSEGV、ANR、所有 Android API 或 ARM 真机。正常 OTA 发布与运行证据另记 `delivery.json`。

正常发布内容 5：预览 OTA7、正式 OTA4，两个 ABI。466 项 Flutter 测试及静态检查通过。373–375 是原正式 AVD 上后台下载、冷启动后演示会话与 29 任务保留、内容 5 当前的截图/XML；安装/更新时间仍为 2026-10-24 08:42:22。交付包保存在 `D:/ENT207/deliverables/LineSight-1.1.54-content5/`，不包含故障标记或验收入口。旧 content4 冻结交付保留，所有模拟器测试结束后关闭。

官网正常安装包与旧体验版兼容升级包已更新内容 5，旧 URL 的稳定升级别名随之更新；历史 APK 不覆盖。`portal-deployment.json` 保存备份位置与发布哈希，`public-https.json` 为服务器侧使用公共域名和受信任 HTTPS 的完整下载校验，两个 APK、主页、脚本、图片、根路径与 `/linesight/` 旧 URL 均通过。仍没有独立外网客户端及浏览器布局验收；本机此前的 TLS EOF 未计为通过。
