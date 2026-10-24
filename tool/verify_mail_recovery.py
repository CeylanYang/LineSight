"""Exercise official Keycloak password recovery in an isolated mail-test realm."""
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import secrets
import subprocess
import time
import traceback
from urllib.parse import urlencode, urljoin
from urllib.request import urlopen
from urllib.error import HTTPError
import uuid

import verify_cloud_sessions as kc


class Page(kc.Form):
    def __init__(self):
        super().__init__(); self.links = []

    def handle_starttag(self, tag, attrs):
        super().handle_starttag(tag, attrs)
        values = dict(attrs)
        if tag == 'a' and values.get('href'):
            self.links.append(values['href'])


def page(client, url, data=None):
    url = urljoin(kc.origin+'/', url)
    with client.open(kc.Request(url, data=urlencode(data).encode() if data is not None else None), timeout=20) as response:
        result = Page(); result.feed(response.read().decode()); return result


def main():
    status, _, admin = kc.call(kc.origin+'/realms/master/protocol/openid-connect/token', urlencode({
        'client_id':'admin-cli', 'grant_type':'password',
        'username':kc.private['KEYCLOAK_ADMIN_USERNAME'],
        'password':kc.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status == 200
    token = admin['access_token']
    realm_name = 'linesight-mail-validation'
    realm_url = kc.origin+'/admin/realms/'+realm_name
    status, _, production = kc.call(kc.origin+'/admin/realms/linesight', token=token)
    assert status == 200 and production['registrationAllowed'] is False
    original_smtp = production.get('smtpServer', {})
    smtp_config = {'host':'10.89.0.1','port':'2525',
        'from':'noreply@99ai.pronhubcn.com','fromDisplayName':'LineSight',
        'auth':'false','ssl':'false','starttls':'false'}
    status, _, existing = kc.call(realm_url, token=token)
    if status == 404:
        status, _, _ = kc.call(kc.origin+'/admin/realms', {
            'realm':realm_name, 'enabled':True, 'registrationAllowed':False,
            'resetPasswordAllowed':True, 'loginWithEmailAllowed':True,
            'smtpServer':smtp_config}, token)
        assert status == 201
        assert kc.call(realm_url+'/clients', {'clientId':'linesight-android', 'enabled':True,
            'publicClient':True, 'standardFlowEnabled':True, 'directAccessGrantsEnabled':False,
            'redirectUris':[kc.redirect], 'attributes':{'pkce.code.challenge.method':'S256'}}, token)[0] == 201
    else:
        assert status == 200 and existing['registrationAllowed'] is False
        assert existing['smtpServer']['host'] == '10.89.0.1'
        assert kc.call(realm_url,{'smtpServer':smtp_config},token,method='PUT')[0] == 204
    kc.issuer = kc.origin+'/realms/'+realm_name
    username = 'mail-probe-'+uuid.uuid4().hex
    address = username+'@example.invalid'
    password = secrets.token_urlsafe(32); replacement = secrets.token_urlsafe(32)
    location = None
    ssh = subprocess.Popen(['ssh', '-i', str(Path.home()/'.ssh/linesight-ali-baot.pem'),
        '-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-N',
        '-L','127.0.0.1:18025:127.0.0.1:8025','root@47.111.81.94'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for attempt in range(15):
            try:
                with urlopen('http://127.0.0.1:18025/api/v1/messages', timeout=2) as r: json.load(r)
                break
            except OSError:
                assert ssh.poll() is None, 'Mail tunnel stopped'; time.sleep(1)
        else: raise AssertionError('Mail API unavailable')
        status, headers, _ = kc.call(realm_url+'/users', {'username':username,'email':address,
            'emailVerified':True, 'enabled':True,'firstName':'Mail','lastName':'Probe',
            'credentials':[{'type':'password','value':password,'temporary':False}]},token)
        assert status == 201; location = headers['Location']
        client = kc.browser()
        params = {'client_id':'linesight-android','response_type':'code','redirect_uri':kc.redirect,
                  'scope':'openid','state':secrets.token_urlsafe(24),
                  'code_challenge':'a'*43,'code_challenge_method':'S256'}
        login = page(client, kc.issuer+'/protocol/openid-connect/auth?'+urlencode(params))
        reset = next(link for link in login.links if '/login-actions/reset-credentials' in link)
        form = page(client, html.unescape(reset))
        action = next(iter(form.forms.values()))
        page(client, html.unescape(action), {'username':username})
        mail = None
        for _ in range(20):
            with urlopen('http://127.0.0.1:18025/api/v1/messages', timeout=5) as r: messages=json.load(r)
            match = next((m for m in messages['messages'] if any(t['Address']==address for t in m['To'])), None)
            if match:
                with urlopen('http://127.0.0.1:18025/api/v1/message/'+match['ID'],timeout=5) as r: mail=json.load(r)
                break
            time.sleep(1)
        assert mail, 'Reset email not received'
        with urlopen('http://127.0.0.1:18025/api/v1/message/'+match['ID']+'/headers',timeout=5) as r:
            headers=json.load(r)
        signature=headers.get('Dkim-Signature',headers.get('DKIM-Signature',[]))
        assert signature and 'd=99ai.pronhubcn.com' in str(signature)
        links = Page(); links.feed(mail['HTML'])
        link = next(html.unescape(u) for u in links.links if u.startswith(kc.issuer+'/login-actions/'))
        change = page(client, link)
        assert 'password-new' in change.fields
        action = change.forms['kc-passwd-update-form']
        # Native callback is deliberately intercepted by the official verifier.
        kc.open_form(client, html.unescape(action), {'password-new':replacement,'password-confirm':replacement})
        kc.authorize(kc.browser(),username,password,expect_denied=True)
        tokens = kc.authorize(kc.browser(),username,replacement)
        assert tokens['access_token'] and tokens['refresh_token']
        # Mail action tokens are one-use; a fresh browser cannot reset again.
        try:
            reused = page(kc.browser(),link)
            assert 'password-new' not in reused.fields
        except HTTPError as error:
            assert error.code in (400, 401, 410)
        _, _, after = kc.call(kc.origin+'/admin/realms/linesight',token=token)
        assert after['registrationAllowed'] is False and after.get('smtpServer',{}) == original_smtp
        result = {'isolated_realm':realm_name,'open_source_smtp':'Mailpit v1.32.0',
            'mail_transport':'Keycloak -> Postfix + OpenDKIM -> Mailpit',
            'domain_dkim_signature_present':True,
            'official_keycloak_reset_email_received':True,'reset_link_completed':True,
            'old_password_rejected':True,'new_password_pkce_login':True,'reset_link_reuse_rejected':True,
            'production_smtp_unchanged':True,'public_registration_closed':True,
            'production_passwords_changed':False,'external_email_delivery_verified':False}
    finally:
        if location:
            assert kc.call(location,token=token,method='DELETE')[0] == 204
        ssh.terminate(); ssh.wait(timeout=10)
        kc.call(kc.origin+'/realms/master/protocol/openid-connect/logout',urlencode({
            'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
    result['disposable_account_deleted'] = True
    folder = Path('docs/product/linesight/acceptance/operations55-batch'); folder.mkdir(parents=True,exist_ok=True)
    (folder/'mail-recovery.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'passed':False,'type':type(error).__name__,
            'frames':[(Path(f.filename).name,f.lineno,f.name) for f in traceback.extract_tb(error.__traceback__)]}))
        raise SystemExit(1)
