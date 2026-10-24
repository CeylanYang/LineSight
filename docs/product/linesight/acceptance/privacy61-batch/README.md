# 8078 原生认证库故障日志补验

2026-10-24，在保留现有数据的 API34 x86_64 模拟器执行。目标 APK 仍为 1.1.54+8078，安装更新时间 05:44:43；只更新了同签名、独立的 instrumentation 测试包。正式 App、账号、数据库、密钥和 OTA 发布均未修改。

`NativePrivacyAudit` 通过冻结 8078 的 R8 映射，直接调用已安装 APK 中的 AppAuth 0.11.1 TokenRequestTask。测试包没有嵌入另一个 AppAuth 副本，未增加生产依赖。内存 HttpURLConnection 提供三类故障：OAuth invalid_grant、非 JSON 响应、IOException。没有外部请求、真实密码或真实令牌。

每种故障必须返回错误回调，且回调异常/原因必须包含其独立合成标记。`tool/audit_native_privacy.py` 对实际安装 APK 的原生及资源指纹与冻结 OTA 基线比对，实时采集 logcat 后只检查测试进程 PID，并仅保存计数和分类。最终三例均通过：采集该进程 29 行日志，三种标记出现次数均为 0。原始日志不写入验收目录或 Git。

运行：先以 preview 签名构建 `:app:assembleReleaseAndroidTest`，只安装 `build/app/outputs/apk/androidTest/release/app-release-androidTest.apk`，然后执行：

```powershell
python tool/audit_native_privacy.py --output docs/product/linesight/acceptance/privacy61-batch/native-appauth.json
```

该测试限定于冻结 8078 的类/字段映射；升级原生基线后必须依据对应 mapping.txt 调整并重新验收。测试期间纠正了辅助代码的构造参数和动态代理差异，不能将辅助测试崩溃归因为产品缺陷。最终测试正常完成后关闭模拟器。

范围限制：这证明当前模拟器日志级别下，三类 AppAuth 令牌故障未输出所注入的响应或异常标记。它不证明全部插件、Flutter 未捕获异常、提高日志级别后的行为、Android 系统崩溃日志或真实设备已完成隐私审计，相关条目继续待验收。
