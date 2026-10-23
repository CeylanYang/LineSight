"""Index existing demonstration PNGs without manufacturing screenshot evidence."""
import hashlib
import html
import json
from pathlib import Path
from urllib.parse import quote
from PIL import Image

root = Path(__file__).resolve().parents[1] / 'docs/product/linesight/acceptance'
groups = {
    'sso': ['SSO-01','SSO-02','SSO-04'],
    'product-batch': ['UI-03','QC-01','QC-02','QC-05','REP-03'],
    'offline-batch': ['OFF-01','OFF-02','OFF-03','COL-03'],
    'query-batch': ['UI-02','REP-01','REP-02','REP-03'],
    'trace-batch': ['UI-09','DAT-02','REP-02'],
    'sync-batch': ['DAT-04','QC-04','OFF-02','REL-04'],
    'workbench-batch': ['UI-01','UI-06','UI-11'],
    'access-batch': ['COL-04','UI-11','COL-02'],
    'history-batch': ['DAT-06','UI-05','QC-03'],
    'feedback-batch': ['UI-08','SEC-02','UI-11','REL-04'],
    'vision-batch': ['VISION-01','VISION-02','SCAN-01'],
    'nfc-batch': ['NFC-01','NFC-02'],
    'closure-batch': ['UI-04','QC-07','COL-02'],
    'access2-batch': ['SEC-05','SEC-06','UI-10','UI-11'],
    'release-batch': ['REL-01','REL-03','UI-11'],
}
items = []
for group, ids in groups.items():
    for path in sorted((root / group).rglob('*.png')):
        with Image.open(path) as picture:
            width, height = picture.size
        items.append({'file':path.relative_to(root).as_posix(), 'title':path.stem,
            'batch':group,'batch_requirement_ids':ids,
            'origin':('android-emulator-screenshot' if '-emulator' in path.name else
                'desktop-component-render' if 'desktop-render' in path.name else
                'generated-trace-code' if '-generated' in path.name else
                'processed-reference-image' if '-processed' in path.name else
                'reference-source-image' if '-source' in path.name else 'android-screenshot'),
            'width':width,'height':height,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'batch_notes':group+'/README.md' if (root/group/'README.md').exists() else None})
report = {'screenshots':len(items),'scope':'Batch IDs describe the batch, not acceptance of every state in each PNG.',
          'items':items,'product_plan_complete':False}
(root/'DEMO_INDEX.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
cards=[]
for row in items:
    uri=quote(row['file'],safe='/')
    origin={'android-emulator-screenshot':'Android 模拟器截图','desktop-component-render':'桌面组件渲染','generated-trace-code':'生成的追溯码','processed-reference-image':'算法处理图','reference-source-image':'参考原图','android-screenshot':'Android 截图'}[row['origin']]
    search=html.escape(' '.join([row['title'],row['batch'],*row['batch_requirement_ids'],origin]),quote=True)
    cards.append(f'''<article data-search="{search}" data-origin="{row['origin']}">
<a href="{uri}" target="_blank"><img loading="lazy" src="{uri}" alt="{html.escape(row['title'])}"></a>
<h2>{html.escape(row['title'])}</h2><p>{origin} · {row['width']}×{row['height']}</p>
<p>{html.escape(row['batch'])}</p><p class="path">{html.escape(row['file'])}</p></article>''')
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>LineSight 功能演示素材</title><style>
*{box-sizing:border-box}body{margin:0;background:#f4f7fb;color:#18243d;font-family:system-ui,sans-serif}header{padding:24px;position:sticky;top:0;background:#fffefbf5;border-bottom:1px solid #dde4ef;z-index:1}h1{font-size:23px;margin:0 0 12px}header p{font-size:13px;color:#59667b}input,select{padding:12px;border:1px solid #bbc9dd;border-radius:8px;max-width:100%;font-size:15px}input{width:440px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:18px;padding:24px}article{background:white;border:1px solid #dce4f0;border-radius:14px;overflow:hidden;padding:12px}article[hidden]{display:none}img{width:100%;height:330px;object-fit:contain;background:#eaf0f8;border-radius:7px}h2{font-size:14px;overflow-wrap:anywhere}article p{font-size:12px;color:#59667b;overflow-wrap:anywhere}.path{user-select:all}a:focus{outline:3px solid #246bfd}</style>
<header><h1>LineSight 功能演示素材</h1><p>点击图片打开原始 PNG。桌面组件渲染与 Android 截图分别标注；需求编号用于查找批次，逐项验收以开发台账及批次记录为准。</p>
<input id="search" type="search" aria-label="搜索素材" placeholder="搜索功能、编号或文件名，如 QC-03 / report / login">
<select id="origin" aria-label="素材来源"><option value="">全部来源</option><option value="android-screenshot">Android 截图</option><option value="android-emulator-screenshot">Android 模拟器截图</option><option value="desktop-component-render">桌面组件渲染</option><option value="generated-trace-code">生成的追溯码</option><option value="processed-reference-image">算法处理图</option><option value="reference-source-image">参考原图</option></select><p id="count"></p></header><main>'''+''.join(cards)+'''</main><script>
const search=document.querySelector('#search'),origin=document.querySelector('#origin'),cards=[...document.querySelectorAll('article')];function filter(){let shown=0;const query=search.value.trim().toLowerCase();for(const card of cards){card.hidden=!(card.dataset.search.toLowerCase().includes(query)&&(!origin.value||card.dataset.origin===origin.value));if(!card.hidden)shown++}document.querySelector('#count').textContent=`${shown} / ${cards.length} 张 PNG`}search.addEventListener('input',filter);origin.addEventListener('change',filter);filter();</script></html>'''
(root/'DEMO_INDEX.html').write_text(page,encoding='utf-8')
print(json.dumps({'screenshots':len(items),'index':str(root/'DEMO_INDEX.html')}))
