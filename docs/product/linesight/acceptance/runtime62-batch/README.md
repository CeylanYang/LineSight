# 内容版本 3：Flutter 未捕获错误日志过滤

修复提交 `92c779d`，客户端仍为 1.1.54+8078。`main()` 在 binding、OTA 和账号初始化前安装正式版本错误处理，覆盖 `FlutterError.onError` 和根 isolate 的 `PlatformDispatcher.onError`。只记录固定来源与类别，不读取异常消息、插件 code/details、堆栈字符串、Flutter context 或 informationCollector。开发模式保留原有诊断行为。此修改没有新增 App 页面或客户可见说明。

新增四项测试：框架错误不调用异常/堆栈的 toString 或诊断 collector；异步插件错误包含模拟令牌、密码、卡号及 URL 时仅输出固定分类并标记已处理；常见异常不输出其输入内容；开发模式保持原处理器。全量 463 项 Flutter 测试通过，之后仅移除两处多余 import，静态检查无问题。

预览 OTA sequence 5、正式 OTA sequence 2，内容版本均为 3，两渠道各包含 arm64-v8a 和 x86_64。四份 Ed25519 清单及载荷大小、SHA-256、APK AOT 字节一致性通过；原生 DEX、manifest、资源、assets 和引擎与冻结 8078 指纹一致。发布工具经 SSH 校验远端上传文件散列，先传载荷再原子切换清单。

原生 API34 x86_64 验证：

- 343：更新已准备好；本轮更新前运行的是内置内容版本 0，不声称本轮覆盖内容 2 到 3 的迁移。
- 冷启动原生诊断显示 `status=PATCHED patch=ota-5`。
- 344：内容版本 3、已是最新内容。
- 345：冷启动后仍为独立演示团队，29 个任务（13 待检、3 异常、13 关闭），没有重新登录或写入客户团队数据。
- App 安装更新时间仍为 2026-10-24 05:44:43，没有重装或清除 App 数据。

第一次模拟器宿主在补截图时以 Windows 访问冲突码 -1073741819 退出，已确认进程终止后重启同一 AVD。原因未定位，不归因为 App 崩溃；第二次启动补齐内容版本和保留登录截图后主动关闭。原始 logcat 不随本批归档。

`tool/record_runtime62_acceptance.py` 校验测试结果、截图/XML、原生日志标记、安装时间、签名及载荷，生成 `validation.json` 和 `D:/ENT207/deliverables/LineSight-1.1.54-content3/` 两种签名 APK 及更新说明。保留原内容版本 2 交付目录。

范围限制：这次故障处理的回归验证在 Flutter 测试运行器中完成，原生设备只验证正常运行及 OTA 生效，未在正式 Android 进程注入 Dart 故障。第三方 Kotlin/Java 的直接 Log/printStackTrace、系统崩溃输出、提高日志级别后的行为、正式签名运行与真实设备尚未整体验收。Dart 处理器不能过滤插件直接写出的原生日志。
