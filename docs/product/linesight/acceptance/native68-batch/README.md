# 首帧之后原生 SIGSEGV 自动回退

2026-10-24，保留数据的独立 `LineSightOtaFaultValidation` AVD，API34 x86_64，正式 8078 基础内容 4。沿用独立同签名 audit APK，将交付内容 5 的正常 x86_64 AOT 仅安装到本机模拟器，然后外部注入 SIGSEGV。没有向公开 OTA 分发故障补丁，没有使用客户账号、重装或清除数据。

此测试覆盖 67 批启动期 Dart 故障之外的路径：**补丁已显示首帧并完成启动后，Android 系统记录进程原生崩溃，下一次启动才识别并回退。**

1. 核对安装 APK 与冻结 content4 SHA-256 一致；本地补丁从冻结 content5 正式包提取，核对设备内 .so SHA-256、加载诊断 PATCHED。
2. 页面显示后确认 `patch_loading=false`。正常 force-stop 再启动仍为 PATCHED，作为不误判用户主动关闭的对照。
3. 核对 App PID、`/proc/PID/cmdline` 与启动保护保存的 PID 相同，仅向此 App PID 发送信号 11。未向宿主或模拟器进程发送信号。
4. Android ApplicationExitInfo 记录 PID 4904，`reason=5 (APP CRASH(NATIVE))`、`status=11`。下一次原生启动诊断为 DROPPED_CIRCUIT_BREAKER，失败计数 1；补丁移除、BOOT_CRASH 黑名单和重复应用拒绝通过。
5. 冷启动工作台恢复，376–377 截图/XML 归档。两张页面外观相同；补丁加载与回退以设备内文件、原生诊断和 Android 退出记录证明。

原 audit 模块安装版本标签仍为 `local-ota67-framework`，这里载荷是**正常内容 5**，摘要与上一批故障载荷不同；本次故障来源是外部 SIGSEGV，并非框架异常。标签及黑名单均只存在隔离测试 AVD 中。

首次脚本误以为未登录个人页具有「应用更新」入口，进入路径检查失败后未注入信号；改为使用原生加载状态和 .so 校验继续。注入成功后系统原因名称与脚本预期格式不同，脚本在退出记录校验处暂停；通过 `--resume-after-crash 4904` 核对保留的 PID、首帧状态和退出记录后继续，未重复注入。完整原始退出信息仅留在忽略目录；仓库只保存此 PID 及正常关闭对照记录。

测试使用本地 userdebug 模拟器临时 adb root 读取保护状态并发送信号，结束后 `adb unroot` 验证 uid 为 2000，然后关闭模拟器释放资源。生产 APK、线上补丁、账号及业务数据均未修改，本轮不需要发布新版。

`validation.json` 保存运行结果；`exit-and-ui-evidence.json` 保存精确退出记录摘录和截图/XML 散列。复现工具为 `tool/verify_native68_rollback.py` 与 `tool/record_native68_evidence.py`。已完成证据会阻止误重跑，不清空黑名单。

本批仅证明 API34 x86_64 的首帧后 SIGSEGV 回退。ANR、其他 Android API、ARM 真机，以及系统崩溃输出中的隐私审计仍待验收，不能由本批替代。
