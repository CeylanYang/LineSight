"""Preview or verify phone layouts against the real portal assets using Chrome."""
import argparse
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--candidate', action='store_true')
parser.add_argument('--legacy', action='store_true')
args = parser.parse_args()
assert not (args.candidate and args.legacy)
OUT = ROOT / 'docs/product/linesight/acceptance/portal71-batch' / ('candidate' if args.candidate else 'live-legacy' if args.legacy else 'live')
OUT.mkdir(parents=True, exist_ok=True)
records = []
with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    try:
        for width in ([390] if args.legacy else [320, 390, 700, 1440]):
            context = browser.new_context(viewport={'width': width, 'height': 900})
            if args.candidate:
                for name in ['index.html', 'mobile.css']:
                    pattern = '**/mobile.css' if name == 'mobile.css' else 'https://99ai.pronhubcn.com/'
                    context.route(pattern, lambda route, request, name=name: route.fulfill(
                        path=str(ROOT / 'deploy/portal' / name)))
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            url = 'https://99ai.pronhubcn.com/' + ('linesight/' if args.legacy else '')
            assert page.goto(url, wait_until='networkidle', timeout=60000).status == 200
            close = page.get_by_role('button', name='关闭开工弹窗')
            if close.is_visible():
                close.click()
            buttons = page.locator('#download a[download]')
            assert buttons.count() == 2
            metrics = buttons.evaluate_all('''nodes => nodes.map(n => {
                const r = n.getBoundingClientRect(); const s = getComputedStyle(n);
                return {text:n.innerText, href:n.href, x:r.x, y:r.y,
                    width:r.width, height:r.height, font:parseFloat(s.fontSize)};
            })''')
            geometry = page.evaluate('''() => ({width:innerWidth,
                documentWidth:document.documentElement.scrollWidth})''')
            assert not errors, errors
            if geometry['documentWidth'] > width:
                print(page.evaluate('''() => [...document.querySelectorAll('body *')]
                    .map(n => ({tag:n.tagName, cls:n.className, id:n.id,
                        right:n.getBoundingClientRect().right}))
                    .filter(n => n.right > innerWidth + 1).slice(0,30)'''))
                page.screenshot(path=str(OUT / f'{width}-overflow.png'))
            assert geometry['documentWidth'] <= width, geometry
            if width <= 700:
                for m in metrics:
                    assert m['height'] >= 44 and m['font'] >= 16, m
                    assert m['x'] >= 0 and m['x'] + m['width'] <= width, m
                assert metrics[1]['y'] < 900, 'Install controls must be visible in first phone screen'
                before = page.locator('#task-state').inner_text()
                page.locator('#advance-task').click()
                assert page.locator('#task-state').inner_text() != before
            page.locator('#download').scroll_into_view_if_needed()
            page.screenshot(path=str(OUT / f'{width}-download.png'))
            records.append({'width': width, 'url': page.url, 'geometry': geometry, 'buttons': metrics,
                            'page_errors': errors, 'task_interaction_checked': width <= 700})
            context.close()
    finally:
        browser.close()
(OUT / 'validation.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'candidate': args.candidate, 'widths_passed': [r['width'] for r in records]}))
