"""Render report diagrams from explicit nodes; no third-party dependencies."""
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def render(name, title, subtitle, height, nodes, edges):
    parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="{height}" viewBox="0 0 1200 {height}">
<defs><marker id="arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="m1 1 5 3-5 3" fill="none" stroke="#86a4ce" stroke-width="1.4"/></marker></defs>
<rect width="1200" height="{height}" rx="24" fill="#f6f9fd"/>
<g font-family="Segoe UI,Microsoft YaHei,sans-serif"><rect x="36" y="34" width="5" height="35" rx="2.5" fill="#3478f6"/><text x="57" y="59" fill="#22334d" font-size="24" font-weight="700">{escape(title)}</text><text x="57" y="91" fill="#7d8da4" font-size="13">{escape(subtitle)}</text>''']
    for points in edges:
        parts.append(f'<polyline points="{points}" fill="none" stroke="#9ab2d2" stroke-width="1.6" stroke-linejoin="round" marker-end="url(#arrow)"/>')
    for x,y,w,h,number,heading,description,color in nodes:
        fill,stroke,accent = ('#edf6f3','#cde8df','#139d83') if color=='green' else ('#eff5ff','#d7e5f9','#3478f6')
        parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{fill}" stroke="{stroke}"/>')
        parts.append(f'<text x="{x+17}" y="{y+26}" fill="{accent}" font-size="10" font-weight="700" letter-spacing="1.2">{escape(number)}</text>')
        parts.append(f'<text x="{x+17}" y="{y+52}" fill="#2e4360" font-size="16" font-weight="650">{escape(heading)}</text>')
        parts.append(f'<text x="{x+17}" y="{y+75}" fill="#7d8da4" font-size="11">{escape(description)}</text>')
    parts.append(f'<path d="M40 {height-52}H1160" stroke="#e1e9f4"/><text x="40" y="{height-26}" fill="#93a4ba" font-size="10">LineSight / Week 6 / Web experience</text></g></svg>')
    (ROOT/(name+'.svg')).write_text('\n'.join(parts),encoding='utf-8')


render('navigation-flow','LineSight · 客户浏览流程','生产、质检、配方与团队信息通过同一组对象串联。每个详情都支持返回与主导航切换。',760,[
    (40,145,220,100,'01 / OVERVIEW','质量工作台','工位概览、任务与质量入口',''),
    (340,145,220,100,'02 / PRODUCTION','生产任务','浏览进度、负责人和交接时间',''),
    (640,145,220,100,'03 / JOB','任务详情','关联工位、配方和质检记录',''),
    (940,145,220,100,'04 / INSPECTION','检测记录','质检状态、图像与任务追溯',''),
    (40,350,220,100,'TEAM','团队工作区','共享任务与成员职责','green'),
    (340,350,220,100,'MEMBER','成员资料','查看负责人及工作职责','green'),
    (640,350,220,100,'ISSUE','异常处理记录','修整要求、负责人和复核进展','green'),
    (940,350,220,100,'IMAGE','图像与轮廓','并排查看、单图查看与放大',''),
    (40,555,220,100,'RECIPES','配方中心','查看材料、版本与检查项目',''),
    (340,555,220,100,'RECIPE','配方详情','检测参数与关联工位',''),
    (640,555,220,100,'STATION','工位详情','设备、当前配方与生产任务',''),
],[
    '260,195 340,195','560,195 640,195','860,195 940,195','1050,245 1050,350',
    '750,245 750,350','640,400 560,400','260,400 340,400',
    '150,350 150,297 450,297 450,245','260,605 340,605','560,605 640,605',
    '750,555 750,505 900,505 900,195 860,195'
])

render('architecture','LineSight · 静态网页架构','运行资源全部随包提供；Hash 路由适用于本地文件和静态托管，构建过程无需下载 npm 依赖。',690,[
    (40,145,240,100,'SOURCE / UI','HTML + CSS + JavaScript','页面、样式、导航与图片查看',''),
    (40,310,240,100,'SOURCE / CONTENT','统一内容与双语文案','任务、记录、配方、工位与成员',''),
    (40,475,240,100,'SOURCE / ASSETS','本地品牌与零件 SVG','三组零件图像及对应轮廓',''),
    (370,310,220,100,'BUILD','Node.js 构建','复制资源并生成 SHA-256 清单',''),
    (660,310,220,100,'DELIVERY','完整 dist/','可独立分发的静态文件','green'),
    (960,145,200,100,'LOCAL','本地浏览','双击 index.html','green'),
    (960,310,200,100,'HOSTING','Vercel / Netlify','静态托管与详情刷新','green'),
    (960,475,200,100,'PREFERENCE','浏览器语言偏好','默认中文，可完整切换英文','green'),
],[
    '280,195 325,195 325,360 370,360','280,360 370,360','280,525 325,525 325,360 370,360',
    '590,360 660,360','880,360 920,360 920,195 960,195','880,360 960,360',
    '880,360 920,360 920,525 960,525'
])
print('Rendered navigation-flow.svg and architecture.svg')
