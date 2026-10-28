# Aurora 与登录广告 · 1.1.60+8084

## 使用

- 应用处于前台时，360ms 内连续按两次音量下键，显示页面边缘 Aurora 流光。
- Aurora 为透明中心的视觉悬浮层，不打开新路由，不调用 AI、不录音、不发业务请求。
- 轻滑、点击业务按钮或按其他按键可关闭。点击、滚动与键盘事件继续交给原页面；系统返回优先关闭光效。
- 原有音量调节保留。离开应用即关闭光效，后台不监听按键。
- 特供版交互式登录成功后展示用户提供的海报，最多 5 秒，右上角“跳过”与倒计时整体透明度 45%，可立即跳过。普通大字版不展示；刷新令牌、恢复会话及切换团队不重复播放。

## 接入方式

上游：https://github.com/tornikegomareli/Aurora

锁定提交：`a3f9296a1e7744529b69d8a9f9e360bf3c8c81bf`。上游为 SwiftUI / Metal，不能直接在 Android 中链接。本次将其锚点色彩混合、噪声扰动圆角矩形 SDF 和衰减突发包络适配为 Flutter fragment shader，原始代码与上游 README 保留在 `third_party/aurora/`。MIT 许可声明保留于应用许可注册表。Canvas 边缘流光作为旧 GPU 的降级效果。

## 功能接口

界面代码可使用同一个控制器：

```dart
final presentation = PresentationScope.of(context);
presentation.showAurora(); // 仅视觉唤起，bool 返回是否可用
presentation.dismissAurora();
```

也可通过 `LineSightApp(presentationController: controller)` 注入控制器；注入时由调用方管理其生命周期。后续 AI 或其他模块可调用此接口，当前没有绑定实际咨询服务。

Android Activity 使用 `linesight/aurora` MethodChannel，双击判定仅在本应用前台有效。没有悬浮窗权限、无障碍服务、后台服务或系统全局按键监听。

## OTA 配置预留

效果、shader 和海报均内置于 APK。沿用现有 Ed25519 签名运行时配置及防降级校验。`deploy/runtime/app-config.json` 已补充以下可选配置：

```json
{
  "presentation": {
    "aurora": {
      "enabled": true,
      "double_press_ms": 360,
      "style": "standard",
      "palette": "intelligence",
      "speed": 0.35,
      "border_width": 3,
      "glow_size": 28,
      "intensity": 0.85
    },
    "login_ad": {"enabled": true, "seconds": 5, "asset": "ai_assistant"}
  }
}
```

- Aurora 可选 `subtle/standard/dramatic`；色盘 `intelligence/ocean/sunset`。
- 双击窗口 200～600ms，广告 1～5 秒，所有数值校验上下限。未知资源、远程代码 URL 及非法字段拒绝加载。
- 配置刷新沿用应用启动、回到前台时的现有机制；关闭 Aurora 后立即撤下已显示光效并停止按键触发。
- 本次只准备配置，没有发布服务器配置。后续用 `tool/publish_runtime_content.py` 生成递增的签名配置版本；安装本次基础包后，可直接远端开关和调整已内置的视觉效果。
- 新增原生按键监听和 shader 的首次接入需要此基础 APK；云端配置不能给旧 APK 增加尚不存在的原生代码。

## 验证

- 518 项 Flutter 测试全部通过，`flutter analyze` 无问题。
- `tool/check_aurora_keys.py` 在 JDK 21 下编译运行真实 Java 双击判定，覆盖双击窗口、长按重复、其他按键、重置与边界。
- 原页面点击穿透、滚动穿透、焦点保留、返回关闭、广告跳过与五秒结束、登录事件去重、签名配置兼容及范围校验均有测试。
- `test/goldens/aurora84-overlay.png` 与 `aurora84-login-ad.png` 为实际 Flutter 渲染核对图。shader 已在测试渲染器加载验证。
- 本轮不运行模拟器；音量实体键、Android 系统返回及不同 GPU 的实机表现仍需设备验收。
