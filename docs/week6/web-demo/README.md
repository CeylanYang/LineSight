# LineSight 静态网页交付证据

本次网页沿用 LineSight 的蓝绿品牌、浅色背景和四个主导航，以生产任务、质检记录、配方与团队构成相互关联的客户浏览路径。桌面为品牌介绍与手机界面并列；手机为全屏界面。默认中文，可完整切换英文。

## 交付物

- 源码及构建/部署说明：[`../../../live-demo/README.md`](../../../live-demo/README.md)
- 导航流程：[`navigation-flow.mmd`](navigation-flow.mmd) / [`navigation-flow.svg`](navigation-flow.svg)
- 静态架构：[`architecture.mmd`](architecture.mmd) / [`architecture.svg`](architecture.svg)
- 工作记录：[`work-log.md`](work-log.md)
- 自动验证结果：[`validation-results.json`](validation-results.json)
- 分发包与构建哈希：[`delivery.json`](delivery.json)
- 可分发 ZIP：[`../../../deliverables/week6/LineSight-web-demo.zip`](../../../deliverables/week6/LineSight-web-demo.zip)
- 页面截图：[`screenshots/README.md`](screenshots/README.md)

网页使用普通 HTML、CSS 与 JavaScript，构建无需下载 npm 依赖。`dist/index.html` 能通过本地文件打开，也能部署在 Vercel、Netlify 等静态托管平台。图片、脚本、样式全部随包提供。

## 产品浏览路径

1. 工作台 → 生产任务 → 传感器固定座 → 检测记录 → 检测图像 → 图片放大。
2. 生产任务 → 仪表保护罩 → 异常处理记录 → 周宁的成员资料。
3. 配方中心 → PLA 精密件 → 工位 01 → 当前生产任务。
4. 我的 → 团队工作区 → 共享任务或团队成员。

网页的交互为导航、视图切换、语言选择和图像查看。它不使用现有部署的账号、令牌或服务端数据。团队名与成员为独立内容，不包含访问凭据。技术范围说明只写在交付文档中，页面采用客户用语。

## 验收依据

`live-demo/verify.py` 使用隔离的无头 Chrome 运行，遍历实际页面链接；检查两种语言、本地文件和 HTTP、五组窗口尺寸、浏览器前进后退、列表滚动位置、详情刷新、语言偏好、图片弹层键盘操作及离线浏览。验证结果以 JSON 为准。

最终浏览器验收：**83 个可访问页面状态，17 组场景，6,126 项断言通过**；无 JavaScript 错误、失败的 HTTP 响应或远端业务请求。覆盖 Chrome；其他浏览器和外部用户测试尚未执行。

截图使用最终构建，通过浏览器的减少动态效果设置等待稳定呈现；未拼接或修改页面内容。它们是网页运行截图，与此前 Android 截图分开归档。
