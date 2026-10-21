# 打开与部署 LineSight

**直接浏览：**解压后双击 `dist/index.html`。请保留完整的 `dist` 文件夹。

**Netlify：**在手动部署页面上传整个 `dist` 文件夹。首页文件 `index.html` 位于该文件夹的根目录。

**Vercel：**使用 Vercel CLI 时，在解压目录运行 `npx vercel ./dist`，按界面选择项目。也可以从 GitHub 导入 LineSight 仓库，Root Directory 设为 `live-demo`，Framework 设为 `Other`，Build Command 设为 `npm run build`，Output Directory 设为 `dist`。

页面使用 `#/...` 地址，详情刷新不需要额外路由规则。所有图片、样式和脚本均包含在 `dist` 内，无需配置环境变量。

右上角或手机顶部的「中文 / EN」可切换语言。底部导航和卡片可进入各页面，左上角箭头用于返回。

## English

Extract the complete archive and open `dist/index.html`. Keep the entire `dist` folder together.

- **Netlify:** Upload the `dist` folder using manual deployment.
- **Vercel:** Run `npx vercel ./dist` from the extracted folder, or import the GitHub repository with `live-demo` as the root directory, `Other` as the framework, `npm run build` as the build command and `dist` as the output directory.

Hash routes support detail-page refresh without rewrites. All assets are local; no environment variables are needed. Select EN to browse in English.
