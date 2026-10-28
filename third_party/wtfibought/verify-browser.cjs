// Credentials are read only from the operator's existing private account file.
// Reports never contain cookies, credentials, authorization codes or tokens.
const { chromium } = require('C:/Users/29668/node_modules/playwright');
const fs = require('fs'), path = require('path'), cp = require('child_process'), assert = require('assert/strict');
const folder = process.env.WIIB_EVIDENCE || '.artifact-work/wtf144/browser';
fs.mkdirSync(folder, {recursive:true});
const accounts = JSON.parse(fs.readFileSync('D:/ENT207/deliverables/LineSight-checkcheck-team/accounts-private.json','utf8').replace(/^\uFEFF/,''));
const origin = 'https://99ai.pronhubcn.com', base = origin + '/linesight/whatif/';
const mobileOnly = process.argv.includes('--mobile-only');
const report = mobileOnly ? JSON.parse(fs.readFileSync(path.join(folder,'verification.json'),'utf8')) :
  {upstream:'mamawai/wtfibought', checks:{}, layouts:[], routes:[], http_errors:[], expected_denials:[], page_errors:0};
let step = 'launch', browser, page;
async function login(context, account) {
  const target = await context.newPage();
  page = target;
  target.on('pageerror', () => report.page_errors++);
  target.on('websocket', socket => socket.on('framereceived', frame => {
    if(String(frame.payload).includes('CONNECTED')) report.checks.stomp_connected = true;
  }));
  target.on('response', r => {
    const url = new URL(r.url());
    if(url.origin === origin && r.status() >= 400) {
      const list = r.status() === 410 && url.pathname.includes('/api/auth/') ? report.expected_denials : report.http_errors;
      list.push({path:url.pathname,status:r.status()});
    }
  });
  await target.goto(base, {waitUntil:'domcontentloaded',timeout:45000});
  await target.locator('#username').fill(account.username);
  await target.locator('#password').fill(account.password);
  await target.locator('#kc-login').click();
  await target.waitForURL(url => url.pathname === '/linesight/whatif/', {timeout:60000});
  await target.waitForFunction(() => {
    try {return !!JSON.parse(localStorage.getItem('wiib-user')).state.token;} catch {return false;}
  }, {}, {timeout:60000});
  await target.locator('h1').first().waitFor({timeout:45000});
  const notice = target.getByRole('button',{name:'我知道了',exact:true});
  if (await notice.count()) await notice.click();
  return target;
}
async function api(target, url, method='GET', body) {
  return target.evaluate(async ({url,method,body}) => {
    const token = JSON.parse(localStorage.getItem('wiib-user')).state.token;
    const r = await fetch('/linesight/whatif/api/' + url, {method, credentials:'same-origin',
      headers:{satoken:token,'X-Lang':'zh','Content-Type':'application/json'},
      ...(body === undefined ? {} : {body:JSON.stringify(body)})});
    return {status:r.status,body:await r.json()};
  }, {url,method,body});
}
async function verifyMobileTabs(target) {
  for(const route of ['portfolio','me','ai','']) {
    step='mobile tab '+(route || 'home');
    // BrowserRouter's root Link intentionally has no trailing slash in basename.
    const pathname='/linesight/whatif'+(route ? '/'+route : '');
    await target.locator(`[data-tabbar] .glass-items a[href="${pathname}"]`).tap();
    await target.waitForURL(url => url.pathname.replace(/\/$/,'') === pathname,{timeout:10000});
  }
  report.checks.mobile_tab_taps=true;
}
(async () => {
  try {
    browser = await chromium.launch({headless:true});
    if(mobileOnly) {
      assert.equal(report.failed_step,'logout and second account');
      assert.equal(report.routes.length,8);
      assert.equal(report.http_errors.length,0);
      const mobileContext=await browser.newContext({viewport:{width:390,height:844},locale:'zh-CN',isMobile:true,hasTouch:true});
      const mobile=await login(mobileContext,accounts[3]);
      await verifyMobileTabs(mobile);
      assert.equal(report.page_errors,0);
      delete report.failed_step; delete report.error;
      report.completed=true;
      report.failed_stage_rerun='mobile root Link selector corrected to actual basename URL; touch navigation reverified';
      fs.writeFileSync(path.join(folder,'verification.json'),JSON.stringify(report,null,2)+'\n');
      console.log(JSON.stringify(report)); return;
    }
    const context = await browser.newContext({viewport:{width:1440,height:1000},locale:'zh-CN'});
    step='registration perimeter';
    assert.equal((await context.request.get(origin+'/register')).status(),410);
    assert.equal((await context.request.post(base+'api/auth/linesight', {headers:{'X-Forwarded-Access-Token':'spoof'}, maxRedirects:0})).status(),302);
    report.checks.anonymous_spoof_denied = true;
    step='existing account login';
    page = await login(context, accounts[0]);
    const current = await api(page,'auth/current');
    assert.equal(current.body.code,0);
    assert.equal(current.body.data.username,accounts[0].username);
    assert.equal(current.body.data.id,1);
    report.checks.existing_admin_identity = true;
    const nativeToken = await page.evaluate(() => JSON.parse(localStorage.getItem('wiib-user')).state.token);
    const protectedHealth = cp.spawnSync('ssh', ['-i','C:/Users/29668/.ssh/linesight-ali-baot.pem','-o','BatchMode=yes',
      'root@47.111.81.94','/opt/linesight/venv/bin/python /var/tmp/linesight-wtf144/verify-session.py'],
      {input:JSON.stringify({token:nativeToken}),encoding:'utf8',timeout:30000});
    assert.equal(protectedHealth.status,0,'Protected service health failed: '+protectedHealth.stderr.split('\n').slice(-2).join(' '));
    report.service_health = JSON.parse(protectedHealth.stdout);
    const tokenUnchanged = await page.evaluate(async () => {
      const token = JSON.parse(localStorage.getItem('wiib-user')).state.token;
      const r = await fetch('/linesight/whatif/api/auth/linesight',{method:'POST',headers:{satoken:token}});
      const result = await r.json();
      return r.ok && result.code === 0 && result.data === token;
    });
    assert.ok(tokenUnchanged);
    report.checks.native_session_reused = true;
    for(const route of ['auth/register','auth/login/local','auth/login/password','auth/callback/linuxdo','auth/mode']) {
      const r = await api(page,route,route.includes('callback') || route.endsWith('mode') ? 'GET' : 'POST',
        route.includes('callback') || route.endsWith('mode') ? undefined : {});
      assert.equal(r.status,410);
    }
    report.checks.local_admin_and_signup_closed = true;
    const health = await page.evaluate(async () => {
      const token = JSON.parse(localStorage.getItem('wiib-user')).state.token;
      // Probe the session-protected application with a normal business request.
      const r = await fetch('/linesight/whatif/api/user/portfolio',{headers:{satoken:token}});
      return (await r.json()).code;
    });
    assert.equal(health,0);
    const stocks = await api(page,'bstock/list');
    assert.equal(stocks.body.code,0); assert.equal(stocks.body.data.length,10);
    assert.equal(stocks.body.data.filter(s=>s.price>0).length,10);
    const klines = await api(page,'bstock/klines?symbol=NVDABUSDT&interval=5m&limit=10');
    assert.ok(Array.isArray(klines.body) && klines.body.length===10);
    report.checks.original_stock_catalogue = true;
    report.checks.live_prices_and_real_stock_klines = true;
    step='settle initial verification transfer';
    const account = (await api(page,'auth/current')).body.data;
    // The first verification discovered upstream's documented 1% transfer fee.
    // Return only that known test deposit; never reset/rewrite account ledgers.
    if(account.balance===9999 && account.gameBalance===0.99) {
      assert.equal((await api(page,'wallet/transfer','POST',{direction:'TO_BALANCE',amount:0.99})).body.code,0);
      report.verification_virtual_transfer_fee = 0.02;
    }
    step='persist profile preference';
    const preference = (await api(page,'user/profile-public')).body.data;
    try {
      assert.equal((await api(page,'user/profile-public','POST',{profilePublic:!preference})).body.code,0);
      assert.equal((await api(page,'user/profile-public')).body.data,!preference);
    } finally {await api(page,'user/profile-public','POST',{profilePublic:preference});}
    report.checks.preference_persists_and_is_restored = true;
    for(const width of [1440,390]) {
      step='original layout '+width;
      await page.setViewportSize({width,height:1000});
      await page.waitForTimeout(1600);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1));
      await page.screenshot({path:path.join(folder,`home-${width}.png`),fullPage:true});
      report.layouts.push({width,horizontal_overflow:false});
    }
    for(const route of ['bstock','coin','portfolio','arena','ai','strategies','backtest','me']) {
      step='route '+route;
      await page.goto(base+route,{waitUntil:'domcontentloaded',timeout:45000});
      await page.locator('header').waitFor({timeout:45000});
      await page.waitForTimeout(1400);
      assert.equal(new URL(page.url()).pathname,'/linesight/whatif/'+route);
      assert.ok((await page.locator('main').innerText()).length > 20);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth+1));
      await page.screenshot({path:path.join(folder,`${route}-390.png`),fullPage:true});
      report.routes.push({route,rendered:true});
    }
    step='logout and second account';
    await api(page,'auth/logout','POST');
    await page.goto(base+'oauth2/sign_out?rd='+encodeURIComponent('/linesight/whatif/'),{waitUntil:'domcontentloaded',timeout:45000});
    await page.locator('#username').waitFor({timeout:30000});
    report.checks.logout_revokes_browser_sso = true;
    const ordinaryContext = await browser.newContext({viewport:{width:390,height:844},locale:'zh-CN',isMobile:true,hasTouch:true});
    const ordinary = await login(ordinaryContext,accounts[3]);
    const member = await api(ordinary,'auth/current');
    assert.equal(member.body.data.username,accounts[3].username);
    assert.ok(member.body.data.id>=100);
    report.checks.ordinary_identity_is_not_admin = true;
    await ordinary.reload({waitUntil:'domcontentloaded'});
    await ordinary.locator('h1').first().waitFor({timeout:45000});
    assert.equal((await api(ordinary,'auth/current')).body.data.id,member.body.data.id);
    report.checks.identity_persists_after_reload = true;
    await verifyMobileTabs(ordinary);
    assert.equal(report.page_errors,0);
    assert.equal(report.http_errors.length,0);
    assert.equal(report.checks.stomp_connected,true);
    report.completed = true;
    fs.writeFileSync(path.join(folder,'verification.json'),JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report));
  } catch(error) {
    if(page) await page.screenshot({path:path.join(folder,'error.png'),fullPage:true}).catch(()=>{});
    report.failed_step = step; report.error = error.name + ': ' + error.message.split('\n')[0].slice(0,220);
    // Error messages must not contain URL query strings from OAuth redirects.
    report.error = report.error.replace(/https?:\/\/\S+/g,'[URL]');
    fs.writeFileSync(path.join(folder,'verification.json'),JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report)); process.exitCode=1;
  } finally {await browser?.close();}
})();
