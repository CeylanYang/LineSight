# 1.1.52+8076 Android 网页登录回调修复

旧版 MainActivity 的 `android:taskAffinity=""` 与 AppAuth 的默认任务栈不同。网页登录完成后，回调接收 Activity 能被唤起，但 AppAuth 管理 Activity 不能可靠地将结果交回等待中的 Flutter 页面。这与 flutter_appauth 12.1.0 README 的 Android setup 已知问题吻合。

移除空 taskAffinity，保留 AppAuth 官方回调 Activity 和 `com.linesight.app:/oauthredirect`，保持追溯链接由 Flutter 主界面接收。没有改用密码直传登录，没有修改服务端客户端、账户或密码。发布脚本增加空 taskAffinity 拦截；独立检查覆盖合并后的回调接收器、共享任务栈、singleTask 管理 Activity 和 Flutter 路由隔离。

模拟器 API34，保留数据覆盖安装 8076 普通预览签名 APK：

1. 旧 8074 输入 `lsuser01` 的密码并提交，停留在 disabled 登录按钮的网页；截图 312。它是问题现象留证，不声称记录了用户手机的“允许打开”弹窗。
2. 升级 8076 后，已有浏览器 SSO 会话通过官方 OIDC 回调完成令牌交换，App 返回该普通账户的独立工作区；截图 313、314。
3. 在 App 退出账户，再发起网页登录，实际再次输入用户名与密码；截图 315（密码遮挡）。提交后自动返回“我的”，显示 `@lsuser01` 与其个人工作区；截图 316。没有调用服务端直传密码接口代替此项原生验证。
4. 强制结束测试 App 进程，再启动，自动恢复同一工作区和登录状态。没有清除应用数据、卸载或修改既有业务任务。

445 项 Flutter 回归和静态检查通过。后端未修改。5 张 PNG 各有 UI XML，凭证及令牌不入证据仓库。两种签名包均验证签名和 ABI；本批原生验证使用预览签名包，正式签名包没有另装至同一模拟器。

参考：flutter_appauth README Android setup：
https://github.com/MaikuB/flutter_appauth#android-setup
https://github.com/MaikuB/flutter_appauth/issues/503#issuecomment-2165906205

安装时选用与原安装签名一致的 APK，直接覆盖升级；7 个初始账户与原密码继续有效。
