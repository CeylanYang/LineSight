"""Prepare the explicitly scoped version handoff; do not claim hardware acceptance."""
import json
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw

root=Path(__file__).resolve().parents[1]
folder=root/'docs/product/linesight/acceptance/section-focus-batch'
folder.mkdir(exist_ok=True)
native=folder.parent/'native50-batch'
files=sorted((native/'png').glob('*.png'))
assert len(files)==18
sheet=Image.new('RGB',(6*220,3*475),'#e9edf3')
draw=ImageDraw.Draw(sheet)
for i,path in enumerate(files):
    with Image.open(path) as pic:
        thumb=ImageOps.contain(pic.convert('RGB'),(210,440))
        sheet.paste(thumb,((i%6)*220,(i//6)*475))
    draw.text(((i%6)*220,(i//6)*475+442),path.name[:28],fill='black')
sheet.save(root/'.artifact-work/native50-contact.png')
(native/'README.md').write_text('''# 1.1.50 原生业务链路验证

18 张 PNG 为 8074 普通签名 APK 的真实模拟器截图，带对应 UI XML。保留原安装数据，覆盖升级成功。

实际完成：统一二级登录、创建任务、负责人改派、未保存返回确认、开始打印、首检四项检查（失败 2 件）、异常交接必填校验、处置、四项复检（通过 2 件）、关闭、不可变历史。创建成功返回工作台不再经过提交表单；输入追溯号可打开刚关闭的任务。

独立 HTTPS 读回验证两轮检验、模板快照、指派历史、处置及报告/CSV/统计一致，详见 live-api.json。第二个 Native51-Section-Focus 任务由 API 创建，仅作导航夹具，未冒充原生创建。

模拟器后续进程退出，报告页面此次未完成原生验证。相机照片、实体扫码、NFC、触觉和双真机未验证。未改动旧任务。
''',encoding='utf-8')
(folder/'README.md').write_text('''# 1.1.51 版本收尾

顶部“处理异常”及任务分段选择现在自动滚动到对应内容，避免点击后看起来无响应；遵循系统和应用的减少动态效果设置。三项小屏交互测试覆盖主操作、历史分段、减少动画，切换分段不产生业务写入。

本版本按用户要求结束开发交付阶段，后续事项单列，不把待真机项目改成已验收。8074 原生链路证据见 ../native50-batch/；8075 定位修复以组件测试为证，未声称最终 APK 完整原生验收。
''',encoding='utf-8')
index=root/'tool/build_demo_index.py'
text=index.read_text(encoding='utf-8')
if "'native50-batch':" not in text:
    text=text.replace('groups = {',"groups = {\n    'native50-batch': ['UI-03','UI-08','QC-02','QC-03','QC-06','QC-08','COL-03','QA-04'],")
    index.write_text(text,encoding='utf-8')
print(json.dumps({'native_png':len(files),'contact_sheet':str(root/'.artifact-work/native50-contact.png')}))
