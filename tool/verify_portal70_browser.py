"""Independent local Chrome HTTPS/render/download acceptance for the public portal."""
import hashlib
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/product/linesight/acceptance/portal70-batch'
OUT.mkdir(parents=True, exist_ok=True)
ORIGIN = 'https://99ai.pronhubcn.com'
result = {'browser': 'local Chrome headless', 'tls_errors_ignored': False, 'pages': []}
EXPECTED = {
    'production': 'e9767aabd40c5b3fa6abf5727ff435aa54a6cb4dc29a1184fcd352207f68019d',
    'preview': 'e00b9e58ed51f7e018d6892e652f1920f4bc554776febc87afe2b8d40ebaa4ae',
}

with sync_playwright() as p:
    browser = p.chromium.launch(channel='chrome', headless=True)
    try:
        for name, path, width, height in [
            ('desktop', '/', 1440, 1000),
            ('mobile', '/', 390, 844),
            ('legacy-path', '/linesight/', 1440, 1000),
        ]:
            context = browser.new_context(viewport={'width': width, 'height': height},
                                          accept_downloads=True)
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            response = page.goto(ORIGIN + path, wait_until='networkidle', timeout=60000)
            assert response.status == 200
            assert 'LineSight' in page.title()
            page.screenshot(path=str(OUT / (name + '.png')), full_page=True)
            close = page.get_by_role('button', name='关闭开工弹窗')
            if close.is_visible():
                close.click()
            page.locator('#download').scroll_into_view_if_needed()
            page.screenshot(path=str(OUT / (name + '-download.png')))
            links = page.locator('a[download]').evaluate_all(
                '(nodes) => nodes.map(n => ({label:n.innerText, url:n.href}))')
            assert any('content5-production.apk' in link['url'] for link in links)
            assert any('content5-preview.apk' in link['url'] for link in links)
            geometry = page.evaluate('''() => ({width:innerWidth,
                documentWidth:document.documentElement.scrollWidth,
                bodyWidth:document.body.scrollWidth})''')
            assert not errors, errors
            assert geometry['documentWidth'] <= width
            result['pages'].append({'name': name, 'url': page.url, 'status': response.status,
                                    'title': page.title(), 'download_links': links,
                                    'geometry': geometry, 'page_errors': errors})
            if name in ['desktop', 'mobile']:
                channel = 'production' if name == 'desktop' else 'preview'
                button = page.locator('#download a[download]').filter(
                    has_text='首次安装正式版' if channel == 'production' else '旧体验版兼容升级')
                with page.expect_download(timeout=120000) as download_info:
                    button.click()
                download = download_info.value
                assert download.failure() is None
                downloaded = Path(download.path())
                digest = hashlib.sha256(downloaded.read_bytes()).hexdigest()
                assert digest == EXPECTED[channel]
                assert downloaded.stat().st_size == 75547520
                result['pages'][-1]['actual_button_download'] = {
                    'channel': channel, 'filename': download.suggested_filename,
                    'sha256': digest, 'bytes': downloaded.stat().st_size}
            else:
                result['pages'][-1]['legacy_download_head'] = []
                for channel in EXPECTED:
                    url = next(link['url'] for link in links if f'-{channel}.apk' in link['url'])
                    head = context.request.head(url)
                    assert head.status == 200
                    assert int(head.headers['content-length']) == 75547520
                    result['pages'][-1]['legacy_download_head'].append(
                        {'channel': channel, 'status': head.status, 'bytes': 75547520})
            context.close()
    finally:
        browser.close()

(OUT / 'browser.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
