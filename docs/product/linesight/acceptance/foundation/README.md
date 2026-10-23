# 权限基础联调证据

2026-10-23，基于 1.1.20 的开发分支；非正式发布包。

## 验证范围

- `backend-tests.txt`：15 项 Django API 回归通过，包含真实 Bearer 令牌、401/403、成员降级写限制、移除/离组撤权、跨团队隔离与管理员保护。
- `flutter-tests.txt`：15 项本机导入授权、原有工作区导出及中英文回归通过。
- `android-journey.txt`：模拟器 `emulator-5554`，真实 SQLite + 独立本地 Django API，完整联调通过。Flutter runner 将业务场景和 tearDownAll 计为两项。
- `flutter-analysis.txt`：静态分析通过。
- `flutter-all-tests.txt`：完整 Flutter 主机测试共 102 项通过。

后端使用 `.artifact-work/permission-demo.sqlite3` 和独立媒体目录，账号随机生成。未操作生产任务或客户数据。测试 APK 安装版本号 8024，保留原包数据；没有作为交付 APK 输出。

## PNG 索引

| 文件 | 演示动作 | 对应 ID |
|---|---|---|
| png/SEC-01-cloud-login-local-access-denied.png | 仅有云端身份时点击本机导入，被拦截且不显示本机数量 | SEC-01 |
| png/SEC-01-authorized-preview-samples-excluded.png | 本机认证后打开预览，默认排除样例记录 | SEC-01 / DAT-04 |
| png/SEC-01-preview-revoked-on-local-lock.png | 预览期间锁定本机会话，立即隐藏数量和内容 | SEC-01 |
| png/COL-01-member-role-confirmation.png | 管理员修改成员角色的确认页 | COL-01 |
| png/COL-01-member-removed.png | 移除成员后刷新成员列表；原令牌接口访问被拒绝 | COL-01 / SEC-05 |
| png/COL-01-last-administrator-protected.png | 最后一位管理员尝试离组，被服务端阻止 | COL-01 |
| png/SEC-02-invalid-token-reauthentication.png | 无效令牌触发重新登录，未混淆为权限不足 | SEC-02 |

截图来自 Android 实际绘制，1080×1920，没有改写 UI 或合成页面。它们记录过渡页面下的功能验证。按用户新增要求，最终客户入口仍需改为统一云端身份和 App 内二级登录页，届时重新留存对应画面。

本证据不代表整个条目验收完成：团队授权版本、持久会话/草稿、统一云端导航、正式签名、双真机及外部用户验收仍待完成。Excel 保持未验收状态。
