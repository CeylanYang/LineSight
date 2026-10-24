# 特供版并行工作区

设置中的「特供版」默认关闭：关闭为大字版；开启进入特供版界面容器。开关保存于本机，云端账户、团队权限、任务与记录由两个版本共用。

独立工作区：`D:\ENT207\LineSight-special-edition`，分支 `feature/special-edition`。从这里进行 User Story Interaction 绘制、界面实现与素材添加。大字版继续在 `C:\Users\29668\LineSight-workspaces\sync-delivery` 开发。

## 修改位置

- `lib/editions/special/special_shell.dart`：特供版界面容器和视觉组件。
- `lib/editions/edition_host.dart`：双版本挂载位置；保留共享页面的 key，切换不重建身份及业务会话。
- `design/special/user-stories/`：用户故事、交互稿、页面状态与素材对应表。
- `assets/special/`：特供版专用图片。新内置素材须加入 pubspec 并发布新的基础 APK；已支持的远端图片可走签名配置更新。
- `deploy/runtime/app-config.json`：公共文档、报告品牌和特供版标题。不得放账号、令牌或密钥。

## 共用边界

业务请求、SSO、NFC、团队权限、离线草稿和 OTA 继续使用现有服务；不要在特供版复制账户或重新实现认证。`CloudShell` 与各业务页继续提供真实功能。当前特供版只提供独立容器和品牌条，完整界面由本工作区继续绘制实现。

每个用户故事建议记录：角色、起点入口、点击行为、目标页、加载/空/失败状态、完成后返回位置、需要的素材。常用功能直接进入工作页，避免重复二级跳转；开发备注留在这里。

## 运行与合并

先运行 `flutter pub get`。本地组件验证用 `flutter test`；真实云端构建沿用签名构建脚本和受保护的本机配置，工作区不会复制凭据。先在各自分支提交，再将 `feature/sync-delivery` 的共享改动合入特供版分支；视觉改动限于特供目录，减少冲突。
