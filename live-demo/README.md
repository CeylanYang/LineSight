# LineSight web experience

LineSight 的独立静态网页，包含中英文页面、四个主导航，以及生产任务、质检、图片、配方和团队详情。

## 直接分发

构建后，将完整 `dist` 文件夹发送给对方。解压后双击 `dist/index.html` 即可浏览；文件夹内的脚本、样式和 assets 需要一起保留。

页面默认中文，右上角或手机顶部可切换英文，也可在「我的 → 页面语言」切换。语言偏好保存在当前浏览器；浏览器限制本地存储时，当前页面仍可切换语言。

推荐浏览路径：

1. 工作台 → 生产任务 → 传感器固定座 → 查看质检记录 → 查看检测图像。
2. 生产任务 → 仪表保护罩 → 查看处理记录 → 成员资料。
3. 配方中心 → PLA 精密件 → 工位 01 → 当前任务。
4. 我的 → 团队工作区 → 成员资料。

## 构建与本地预览

需要 Node.js 18 或更新版本。项目没有 npm 依赖，无需 `npm install`。

```sh
cd live-demo
npm run build
npm run preview
```

预览地址：`http://127.0.0.1:4173`。可通过 `PORT` 环境变量更改端口。

`src/` 是源文件；构建会刷新 `dist/` 并生成带 SHA-256 的 `build-manifest.json`。

安装了 Python 3 的环境可运行 `python package.py`，校验构建哈希并生成包含 `dist/`、打开/部署说明和清单的 ZIP，默认输出到仓库的 `deliverables/week6/LineSight-web-demo.zip`。

## Netlify

- 直接将 `dist` 文件夹拖入 Netlify 的手动部署界面。
- 或导入仓库，将 Base directory 设为 `live-demo`；构建命令为 `npm run build`，Publish directory 为 `dist`。目录内附有 `netlify.toml`。

## Vercel

- 导入仓库，将 Root Directory 设为 `live-demo`，Framework Preset 选择 `Other`。
- 构建命令为 `npm run build`，Output Directory 为 `dist`；目录内附有 `vercel.json`。
- 路由使用 `#/...`，无需服务器重写规则；刷新详情链接可保留当前位置。

## 浏览器验证

安装了 Python Playwright 和 Chrome 的开发环境可以运行：

```sh
python verify.py --http http://127.0.0.1:4173/
```

该检查使用隔离的无头浏览器，覆盖本地文件、HTTP、页面跳转、两种语言、窄屏布局、图片查看、浏览器历史以及离线打开。截图和结果保存在 `docs/week6/web-demo/`。

运行资源全部随包提供。页面使用独立的固定内容，不读取 Flutter 数据库、远端账户或任何业务服务。
