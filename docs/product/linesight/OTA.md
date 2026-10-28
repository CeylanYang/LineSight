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

* App 内置 Ed25519 公钥；私钥正式副本位于 `C:/Users/29668/LineSight-private/ota-signing-v2/patch-signing.pem`；工作区副本仅为备用。发布工具默认读取正式副本，可通过 `LINESIGHT_OTA_SIGNING_KEY` 指定恢复路径，须单独备份，不能上传到公开目录或提交 Git。
* Dart 层用现有 `cryptography` 校验签名，**所有支持的 Android 版本均校验**，不依赖上游仅 Android 13+ 可用的原生 Ed25519。
* 签名覆盖 SHA-256、大小、序号、有效期、签名通道、基础 versionCode 和 ABI。先验签，再下载、核对 SHA-256，最后交给插件原子安装。
* 预览/正式通道独立；发布器冻结基础 APK 的原生代码、引擎、Manifest、资源与 assets 字节指纹，变化即拒绝打补丁。两种 ABI 分开发送。
* 序号单调增加，回退也是高序号签名命令；安装成功后才记录序号。上游启动崩溃保护会退回基础包并拉黑故障补丁，不主动清空黑名单。
* 内容版本 5 在模块初始化后过滤传给其启动故障钩子的异常，仅保留固定来源/类别及空堆栈，避免原生回滚日志输出原始错误。API34 x86_64 已实际验证框架/异步启动错误触发移除、黑名单、拒绝再次应用及基础包恢复，见 `acceptance/ota67-batch/`；首帧后原生 SIGSEGV 回退及正常关闭不误判也已补验，见 `acceptance/native68-batch/`。ANR、其他 Android API 与 ARM 真机仍待验收。
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


## 8102 基座准备检查（2026-10-25 / Batch135）

正式包1.1.68+8102已冻结546项原生、引擎、资源及元数据指纹，交付目录附ota-base-fingerprint.json。线上两种ABI清单均为204（没有发布补丁），服务器经HTTPS验证。当前工作区文档指定的OTA签名私钥缺失，项目及Codex配置目录按已知文件名搜索未找到；签名公私钥匹配检查未完成，不能声称此版本已具备可操作的补丁发布能力。需要恢复与lib/ota_key.dart匹配的原私钥，不能运行init-key生成替代密钥。没有发布或轮换密钥。证据 acceptance/ota135-batch。


## 发布器签名前检查（Batch137）

pack/rollback 在写补丁或清单之前检查原私钥是否存在、可读取、为Ed25519且与App内置公钥逐字节匹配。缺失或不匹配时输出恢复原密钥的固定提示，不生成替代密钥、不修改信任锚点、不输出密钥内容。4项发布工具测试通过，覆盖缺失、错误/损坏密钥、正确密钥签验及失败时无补丁输出。原私钥仍未恢复，尚不能发布新补丁；此修改仅涉及开发发布工具，不改变已安装App。证据 acceptance/ota137-batch。


## 用户授权密钥轮换（Batch141）

2026-10-25用户明确授权重置并保存在本地。服务器已查常用密钥/备份目录，未发现匹配旧信任锚的Ed25519私钥。已生成v2私钥，正式副本在受限本机用户目录LineSight-private/ota-signing-v2，工作区保留受限备用副本；服务器root私有目录ota-signing-v2保存匹配副本，目录0700/文件0600。发布工具默认读取本机用户密钥库，不再依赖临时工作区路径。

新基础包1.1.68+8104已内置新公钥，arm64-v8a及x86_64均确认新公钥存在、旧公钥不存在；Android生产签名证书不变。631项客户端测试、静态分析、4项签名工具测试及实际密钥签验通过。官网APK哈希已经HTTPS核对。旧8103及之前安装包必须手动覆盖升级基础APK一次，不能接受v2密钥直接签发的补丁。未改旧基座清单，未发布探针或跨密钥补丁。原密钥缺失阻碍已由授权轮换和新包交付解除，独立保管介质和物理设备验证仍未完成。证据 acceptance/ota141-batch。

## 内容版本31（Batch142）

股票原版入口和域名认证兼容修复以8104基座发布OTA序号31。546项原生/资源/引擎指纹逐项一致；两种ABI补丁均在服务器经HTTPS完整下载、SHA-256及v2签名验证，旧8103清单未改动。官网提供同基座内容31完整正式APK。634项Flutter测试、119项后端测试及静态分析通过。证据acceptance/stock142-batch。

公共配置revision2仍使用旧信任锚，已保留所有业务内容，仅提高revision至3、更新有效期并以v2密钥签发；HTTPS字节及验签通过。旧8103及以前仍需要覆盖安装新基座一次。

## 内容31连接故障恢复（2026-10-25）

8104基座发布修复补丁32，原546项冻结指纹一致。内容31的网络连接本身可能失败，不能承诺通过该通道自动恢复；此时覆盖安装同签名1.1.69+8105完整包一次，不卸载、不清数据。新versionCode让上游加载器拒绝旧8104补丁，避免同基座APK被故障补丁继续覆盖。8105基座指纹已单独冻结。后续Dart/API/配置/OTA网络使用固定可信TLS备用连接，证书和Ed25519签名校验保持。详见CONNECTION_143.md。
