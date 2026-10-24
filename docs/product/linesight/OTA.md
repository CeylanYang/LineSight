# Android 自托管 OTA

采用 [flutter_patcher 0.1.4](https://github.com/xuelinger2333/flutter_patcher)（MIT）。
不使用 Shorebird 托管服务，无额外订阅。首次需要升级到带插件的基础 APK。

## 更新行为

启动时并行检查，后台下载，**下次进程冷启动**加载。不会自动重启、退出登录或覆盖正在编辑的表单。
“我的 → 应用更新”可主动检查；本机工作区设置也有入口。断网继续使用现有内容。
当前仅发布 `libapp.so`，覆盖 Dart 页面、路由、业务逻辑和纯 Dart 依赖。
原生插件、Kotlin/Java、权限、Manifest、Flutter 引擎、打包资源或字体发生变化时必须发布新 APK。
上游还支持资源覆盖，本次不启用，避免资源与原生版本漂移。

## 方案比较（2026-10-24 核查上游）

| 项目 | 自托管 | 适配当前工程的结论 |
|---|---|---|
| [flutter_patcher](https://github.com/xuelinger2333/flutter_patcher) | 支持，MIT | Android AOT 加载器插件，上游声称验证 Flutter 3.19～3.44；本工程实际验证见验收目录 |
| [inhouse-codepush](https://github.com/shivanshu877/inhouse-codepush) | 支持，MIT | 需维护引擎/embedding 补丁，运维成本较高 |
| [flutter_eval](https://github.com/ethanblake4/flutter_eval) | 支持，BSD-3 | 自有字节码解释器，需要绑定和改造，不支持全部现有 Dart/Flutter API |
| [Fair](https://github.com/wuba/Fair) | 支持，BSD | pub 最新 4.0.0 的 Dart SDK 约束仍为 `<3.0.0`，不能直接加入当前 Dart 3.12 工程 |
| [RFW](https://github.com/flutter/packages/tree/main/packages/rfw) | 支持，BSD | 适合服务端描述表单/卡片，不能代替完整业务代码 OTA |
| [Shorebird](https://docs.shorebird.dev/code-push/faq/#can-you-self-host-shorebird) | 官方不支持 | 不符合自托管要求 |

## 信任与兼容

* App 内置 Ed25519 公钥；私钥只存在 `.artifact-work/ota/patch-signing.pem`，须单独备份，不能上传到公开目录或提交 Git。
* Dart 层用现有 `cryptography` 校验签名，**所有支持的 Android 版本均校验**，不依赖上游仅 Android 13+ 可用的原生 Ed25519。
* 签名覆盖 SHA-256、大小、序号、有效期、签名通道、基础 versionCode 和 ABI。先验签，再下载、核对 SHA-256，最后交给插件原子安装。
* 预览/正式通道独立；发布器冻结基础 APK 的原生代码、引擎、Manifest、资源与 assets 字节指纹，变化即拒绝打补丁。两种 ABI 分开发送。
* 序号单调增加，回退也是高序号签名命令；安装成功后才记录序号。上游启动崩溃保护会退回基础包并拉黑故障补丁，不主动清空黑名单。
* 只读下载接口无账户数据，不要求登录。没有公开上传/注册入口；发布通过 SSH，先放不可变代码文件，最后原子切换 manifest。
* 开源模块较新，使用的是 Android FlutterLoader 内部加载机制。升级 Flutter/插件必须发布新基础包并重复冷启动验证。当前无物理手机，模拟器验证不能替代真机覆盖。

## 发布

使用带 cryptography 的项目 Python，工作目录为仓库根目录：

```powershell
# 首次初始化密钥（已有密钥时复用，严禁随意更换）
python tool/ota_release.py init-key

# 构建并交付基础 APK 后冻结指纹，两种签名通道分别执行
.\tool\build_signed_delivery.ps1 -Track preview -EvidenceBatch ota54
python tool/ota_release.py base --track preview --base 8078 --apk .artifact-work/release/LineSight-1.1.54-8078-preview.apk

# 仅修改 Dart，保持原生配置、assets、pubspec version 与 Flutter SDK 不变
.\tool\build_signed_delivery.ps1 -Track preview -OtaRevision 1 -EvidenceBatch ota54-patch
python tool/ota_release.py pack --track preview --base 8078 --sequence 1 --apk .artifact-work/release/LineSight-1.1.54-8078-preview.apk
python tool/ota_release.py upload --track preview --base 8078

# 必要时签发高序号回退命令（下次冷启动回到基础 APK）
python tool/ota_release.py rollback --track preview --base 8078 --sequence 2
python tool/ota_release.py upload --track preview --base 8078
```

正式通道同样操作，把 `preview` 替换为 `production`。基础 APK 必须在独立交付目录保存，补丁构建会覆盖构建暂存目录。
同一通道/基础版本禁止重用序号；每次新补丁均需提高序号。
服务器目录 `/var/lib/linesight/ota/{track}/{base}/{abi}`，API 路径 `/api/v1/ota/{track}/{base}/{abi}/manifest.json`。
无更新返回 204。密钥轮换需要新基础 APK。此发布流程不提供 APK 静默安装。
