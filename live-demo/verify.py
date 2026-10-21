"""Isolated browser acceptance checks for the portable LineSight pages."""
from __future__ import annotations

import argparse
from collections import deque
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sys

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parent
EVIDENCE = ROOT.parent / 'docs/week6/web-demo'
SCREENS = EVIDENCE / 'screenshots'
FORBIDDEN = re.compile(r'模拟|仅供演示|原型|免责声明|未接入|测试数据|placeholder|prototype|mock data|demo.only|simulation', re.I)


def run(http: str) -> dict:
    results = []
    errors = []
    remote_requests = []
    bad_responses = []
    checks = 0
    SCREENS.mkdir(parents=True, exist_ok=True)

    def check(condition, description):
        nonlocal checks
        checks += 1
        if not condition:
            raise AssertionError(description)

    def move(page, route):
        page.evaluate('(r) => { location.hash = "#/" + r; }', route)
        page.wait_for_function('(r) => document.querySelector("#app-content").dataset.route === r', arg=route)

    def set_language(page, language):
        page.locator(f'[data-language={language}]').click()
        check(page.locator('html').get_attribute('lang') == ('en' if language == 'en' else 'zh-CN'), f'Language {language}')

    def audit(page, route, language):
        body = page.locator('#app-content').inner_text()
        check(bool(body.strip()), f'{route}: empty page')
        check(FORBIDDEN.search(body) is None, f'{route}: internal narration')
        check('undefined' not in body and '[object Object]' not in body, f'{route}: invalid content')
        if language == 'en':
            check(re.search(r'[\u4e00-\u9fff]', body) is None, f'{route}: untranslated Chinese')
        page.wait_for_function('Array.from(document.images).every(n => n.complete)')
        check(page.locator('img').evaluate_all('(ns) => ns.every(n => n.naturalWidth > 0)'), f'{route}: missing image')
        check(page.locator('.art-panel').evaluate_all('(ns)=>ns.every(n=>n.querySelector("img").getBoundingClientRect().height<=n.getBoundingClientRect().height)'), f'{route}: cropped part image')
        for selector in ['html', '.phone-screen', '#app-content', '#bottom-nav']:
            check(page.locator(selector).evaluate('(n) => n.scrollWidth <= n.clientWidth + 1'), f'{route}: overflow in {selector}')
        check(page.locator('#bottom-nav [aria-current=page]').count() == 1, f'{route}: active navigation')

    with sync_playwright() as p:
        browser = p.chromium.launch(channel='chrome', headless=True)
        context = browser.new_context(viewport={'width': 390, 'height': 844}, reduced_motion='reduce')
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.on('request', lambda request: remote_requests.append(request.url) if not request.url.startswith((http, 'file:', 'data:')) else None)
        page.on('response', lambda response: bad_responses.append({'url':response.url,'status':response.status}) if response.status >= 400 else None)
        page.goto(http, wait_until='load')
        check(page.locator('html').get_attribute('lang') == 'zh-CN', 'Fresh browser defaults to Chinese')

        # Discover every page exposed by actual navigation, including object details and tabs.
        visited = set()
        queue = deque(['home'])
        while queue:
            route = queue.popleft()
            if route in visited:
                continue
            check(len(visited) < 100, 'Route crawl is finite')
            move(page, route)
            audit(page, route, 'zh')
            visited.add(route)
            links = page.locator('a[href^="#/"]').evaluate_all('(ns)=>ns.map(n=>n.getAttribute("href").slice(2))')
            for link in links:
                if link not in visited:
                    queue.append(link)
        routes = sorted(visited)
        results.append({'scenario':'Discover and open every linked Chinese route','status':'pass','routes':len(routes)})

        # Open every route through both file:// and HTTP, in both languages.
        for protocol, base in [('http', http), ('file', (ROOT/'dist/index.html').as_uri())]:
            for language in ['zh', 'en']:
                page.goto(base + '#/home', wait_until='load')
                set_language(page, language)
                for route in routes:
                    move(page, route)
                    audit(page, route, language)
                results.append({'scenario':f'All linked routes: {protocol}, {language}','status':'pass','routes':len(routes)})

        # Each supported width must remain free of horizontal scrolling, in both languages.
        page.goto(http, wait_until='load')
        for width, height in [(360,800),(390,844),(768,1024),(1440,960),(1280,720)]:
            page.set_viewport_size({'width':width,'height':height})
            for language in ['zh','en']:
                set_language(page, language)
                for route in routes:
                    move(page, route)
                    check(page.locator('#app-content').evaluate('(n)=>n.scrollWidth<=n.clientWidth+1'), f'{width} {language} {route}: content overflow')
                    check(page.locator('html').evaluate('(n)=>n.scrollWidth<=n.clientWidth+1'), f'{width} {language} {route}: document overflow')
            results.append({'scenario':f'Layout at {width}×{height}, both languages','status':'pass','routes':len(routes)*2})

        # Walk actual links through production, inspection, images, issue ownership and recipes.
        page.set_viewport_size({'width':390,'height':844})
        set_language(page,'zh')
        move(page,'home')
        page.locator('#app-content a[href="#/jobs"]').click()
        page.locator('#app-content a[href="#/jobs/1041"]').click()
        check('传感器固定座' in page.locator('#app-content').inner_text(),'Job detail')
        page.locator('#app-content a[href="#/records/2041"]').click()
        page.locator('#app-content a[href="#/evidence/2041"]').click()
        page.locator('[data-image="2041"][data-edge="false"]').click()
        check(page.locator('[role=dialog]').is_visible(),'Image viewer opens')
        check(page.locator('#app-content').evaluate('(n)=>n.inert'),'Background is inert')
        page.keyboard.press('Tab')
        check(page.locator('[data-action=close-image]').evaluate('(n)=>n===document.activeElement'),'Dialog keyboard focus')
        page.keyboard.press('Escape')
        check(page.locator('#image-overlay').is_hidden(),'Escape closes image viewer')
        page.locator('[data-image="2041"][data-edge="true"]').click()
        page.locator('[data-action=close-image]').click()
        check(page.locator('#image-overlay').is_hidden(),'Close button closes image viewer')
        page.locator('[data-action=back]').click()
        check(page.locator('#app-content').get_attribute('data-route')=='records/2041','Back returns to inspection')
        page.go_forward()
        check(page.locator('#app-content').get_attribute('data-route')=='evidence/2041','Browser Forward restores images')
        move(page,'jobs/1043')
        page.locator('#app-content a[href="#/issues/1043"]').click()
        page.locator('#app-content a[href="#/members/zhou"]').click()
        check('周宁' in page.locator('#app-content').inner_text(),'Issue links to responsible member')
        move(page,'recipes/pla')
        page.locator('#app-content a[href="#/stations/01"]').click()
        page.locator('#app-content a[href="#/jobs/1041"]').click()
        check('传感器固定座' in page.locator('#app-content').inner_text(),'Recipe → station → job')
        results.append({'scenario':'Actual link journeys, image dialog and browser Back/Forward','status':'pass'})

        move(page,'records')
        link=page.locator('#app-content a[href="#/records/2048"]')
        link.scroll_into_view_if_needed()
        scroll=page.locator('#app-content').evaluate('(n)=>n.scrollTop')
        link.click()
        page.locator('[data-action=back]').click()
        check(abs(page.locator('#app-content').evaluate('(n)=>n.scrollTop')-scroll)<2,'Back restores record-list position')
        results.append({'scenario':'List scroll position preserved on Back','status':'pass'})

        for language, expected in [('zh','传感器固定座'),('en','Sensor mount')]:
            move(page,'jobs/1041')
            page.locator('#app-content').evaluate('(n)=>n.scrollTop=180')
            scroll=page.locator('#app-content').evaluate('(n)=>n.scrollTop')
            set_language(page,language)
            check(page.locator('#app-content').get_attribute('data-route')=='jobs/1041','Language preserves detail route')
            check(expected in page.locator('#app-content').inner_text(),'Detail language updated')
            check(abs(page.locator('#app-content').evaluate('(n)=>n.scrollTop')-scroll)<2,'Language preserves position')
        page.reload(wait_until='load')
        check(page.locator('html').get_attribute('lang')=='en','Language survives reload')
        check(page.locator('#app-content').get_attribute('data-route')=='jobs/1041','Reload preserves detail route')
        results.append({'scenario':'Language switching, persistence and deep-link reload','status':'pass'})

        for route in ['missing','jobs/unknown','recipes/unknown','jobs/1041/extra']:
            page.goto(http+'#/'+route,wait_until='load')
            check(page.locator('#app-content').get_attribute('data-route')=='home','Unknown route falls back to home')
        page.goto(http+'#/jobs/1041',wait_until='load')
        page.locator('[data-action=back]').click()
        check(page.locator('#app-content').get_attribute('data-route')=='jobs','Direct deep-link Back has safe parent')
        results.append({'scenario':'Unknown routes and direct-entry Back','status':'pass'})

        # Fixed data must agree across summaries and linked pages.
        numbers=page.evaluate('''() => {
          const d=window.LS_DATA;
          const done=d.records.filter(r=>r.result!=='pending');
          return {complete:done.length,passed:done.filter(r=>r.result==='pass').length,
            review:d.records.filter(r=>r.result!=='pass').length,
            valid:d.jobs.every(j=>d.stations.some(s=>s.id===j.station)&&d.recipes.some(r=>r.id===j.recipe)&&d.members.some(m=>m.id===j.owner)&&(!j.record||d.records.some(r=>r.id===j.record&&r.job===j.id)))&&d.records.every(r=>d.jobs.some(j=>j.id===r.job)&&d.stations.some(s=>s.id===r.station)&&d.recipes.some(p=>p.id===r.recipe)&&d.members.some(m=>m.id===r.reviewer))};
        }''')
        check(numbers['valid'],'All data references are valid')
        move(page,'home')
        metrics=page.locator('.metric strong').all_text_contents()
        check(metrics==[str(numbers['complete']),f"{numbers['passed']/numbers['complete']*100:.1f}%",str(numbers['review'])],'Summary metrics agree with records')
        results.append({'scenario':'Data references and summary consistency','status':'pass','totals':numbers})

        # Save review-ready screenshots after animations are disabled by reduced motion.
        captures=[
            (1440,960,'zh','home','desktop-zh-home'),(1440,960,'en','home','desktop-en-home'),
            (390,844,'zh','home','mobile-zh-home'),(390,844,'en','home','mobile-en-home'),
            (390,844,'zh','jobs','mobile-zh-jobs'),(390,844,'en','jobs/1041','mobile-en-job-detail'),
            (390,844,'zh','jobs/1041','mobile-zh-job-detail'),(390,844,'zh','evidence/2042','mobile-zh-evidence'),
            (390,844,'en','evidence/2042','mobile-en-evidence'),(390,844,'zh','team','mobile-zh-team'),
            (390,844,'en','team','mobile-en-team'),(390,844,'zh','issues/1043','mobile-zh-issue'),
            (390,844,'zh','recipes','mobile-zh-recipes'),(390,844,'en','recipes','mobile-en-recipes'),
            (390,844,'zh','records','mobile-zh-records'),(390,844,'zh','insights','mobile-zh-insights'),
            (390,844,'zh','me','mobile-zh-profile'),(360,800,'en','team','narrow-en-team'),
            (768,1024,'en','jobs/1041','tablet-en-job-detail')]
        for width,height,language,route,name in captures:
            page.set_viewport_size({'width':width,'height':height})
            set_language(page,language)
            move(page,route)
            page.locator('#app-content').evaluate('(n)=>n.scrollTop=0')
            page.screenshot(path=str(SCREENS/(name+'.png')))
        results.append({'scenario':'Final screenshots','status':'pass','count':len(captures)})

        context.close()
        offline=browser.new_context(viewport={'width':390,'height':844},offline=True,reduced_motion='reduce')
        local=offline.new_page()
        local.on('pageerror', lambda error: errors.append(str(error)))
        local.goto((ROOT/'dist/index.html').as_uri(),wait_until='load')
        local.locator('#app-content a[href="#/jobs"]').click()
        local.locator('#app-content a[href="#/jobs/1041"]').click()
        local.locator('#app-content a[href="#/records/2041"]').click()
        local.locator('#app-content a[href="#/evidence/2041"]').click()
        check(local.locator('.evidence-tile img').evaluate_all('(ns)=>ns.every(n=>n.complete&&n.naturalWidth>0)'),'Offline file journey and images')
        results.append({'scenario':'Offline file:// journey in a fresh browser context','status':'pass'})
        offline.close()
        browser.close()
    check(not errors,f'JavaScript errors: {errors}')
    check(not remote_requests,f'Unexpected remote requests: {remote_requests}')
    check(not bad_responses,f'Failed HTTP responses: {bad_responses}')
    return {'status':'pass','checked_at':datetime.now(timezone.utc).isoformat(),'checks':checks,'routes':routes,'scenarios':results,'javascript_errors':errors,'remote_requests':remote_requests,'failed_responses':bad_responses}


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--http',default='http://127.0.0.1:4173/')
    args=parser.parse_args()
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    try:
        report=run(args.http.rstrip('/')+'/')
    except Exception as error:
        report={'status':'failed','checked_at':datetime.now(timezone.utc).isoformat(),'error':str(error)}
        (EVIDENCE/'validation-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        raise
    (EVIDENCE/'validation-results.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':report['status'],'checks':report['checks'],'routes':len(report['routes']),'scenarios':len(report['scenarios'])},ensure_ascii=False))
