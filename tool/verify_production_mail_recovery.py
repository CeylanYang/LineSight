"""Disposable production-realm reset using only the matching test mailbox message.

Secrets and action links stay in memory. Existing team accounts are untouched.
"""
import base64
import html
import json
from pathlib import Path
import secrets
import subprocess
import traceback
import uuid

import verify_cloud_sessions as kc
from verify_mail_recovery import Page, page


def receive_reset(username, anchor=None):
    private = json.loads((Path.home() / 'LineSight-private/smtp/relay-private.json').read_text(encoding='utf-8-sig'))
    private['probe'] = username
    private['anchor'] = anchor
    # Limit retrieval to new reset messages from the configured sender. Verify
    # the action token subject against the disposable account before using it.
    remote = '''import email,imaplib,json,sys,time
from email.header import decode_header,make_header
v=json.load(sys.stdin)
try:
 with imaplib.IMAP4_SSL('imap.163.com',993,timeout=25) as c:
  c.login(v['username'],v['authorization_code'].strip())
  imaplib.Commands['ID']=('AUTH',)
  c._simple_command('ID','("name" "LineSight" "version" "1.0" "vendor" "LineSight")')
  c.select('INBOX',readonly=True)
  if v['anchor'] is None:
   status,all_ids=c.uid('search',None,'ALL')
   assert status=='OK'
   print(json.dumps({'anchor':max([int(x) for x in all_ids[0].split()]+[0])+1}));sys.exit(0)
  for attempt in range(20):
   status,ids=c.uid('search',None,'ALL')
   if status=='OK' and ids[0]:
    candidates=[u for u in ids[0].split() if int(u)>=v['anchor']]
    if not candidates: time.sleep(2);continue
    uid=candidates[-1]
    status,head=c.uid('fetch',uid,'(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])')
    header=email.message_from_bytes(next(x[1] for x in head if isinstance(x,tuple)))
    subject=str(make_header(decode_header(header.get('Subject',''))))
    if email.utils.parseaddr(header.get('From',''))[1].lower()!=v['sender'].lower() or subject not in ('Reset password','重置密码'):
     time.sleep(2);continue
    status,data=c.uid('fetch',uid,'(BODY.PEEK[])')
    assert status=='OK'
    m=email.message_from_bytes(next(x[1] for x in data if isinstance(x,tuple)))
    body=''.join(p.get_payload(decode=True).decode(p.get_content_charset() or 'utf-8',errors='replace') for p in m.walk() if p.get_content_type()=='text/html')
    print(json.dumps({'html':body}));break
   time.sleep(2);c.noop()
  else: print(json.dumps({'error':'matching_message_not_received'}))
except Exception as e: print(json.dumps({'error':type(e).__name__}))
'''
    code = base64.b64encode(remote.encode()).decode()
    result = subprocess.run(['ssh','-o','BatchMode=yes','-i',str(Path.home()/'.ssh/linesight-ali-baot.pem'),
        'root@47.111.81.94', '/opt/linesight/venv/bin/python -c "import base64;exec(base64.b64decode(\''+code+'\'))"'],
        input=json.dumps(private), text=True, capture_output=True, timeout=100)
    assert result.returncode == 0, 'Mailbox verifier transport failed'
    message = json.loads(result.stdout)
    if anchor is None:
        if 'anchor' not in message:
            print(json.dumps({'mailbox_error_type':message.get('error','unknown')}))
            raise AssertionError('Mailbox anchor failed')
        return message['anchor']
    assert 'html' in message, 'Targeted mailbox read failed: '+message.get('error','unknown')
    return message['html']


def admin_login():
    status,_,admin=kc.call(kc.origin+'/realms/master/protocol/openid-connect/token',kc.urlencode({
        'client_id':'admin-cli','grant_type':'password','username':kc.private['KEYCLOAK_ADMIN_USERNAME'],
        'password':kc.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200
    return admin


def main():
    status,_,admin=kc.call(kc.origin+'/realms/master/protocol/openid-connect/token',kc.urlencode({
        'client_id':'admin-cli','grant_type':'password','username':kc.private['KEYCLOAK_ADMIN_USERNAME'],
        'password':kc.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status == 200
    token=admin['access_token']; realm=kc.origin+'/admin/realms/linesight'; location=None
    username='mail57-'+uuid.uuid4().hex
    password=secrets.token_urlsafe(32); replacement=secrets.token_urlsafe(32)
    try:
        status,_,before=kc.call(realm,token=token)
        assert status==200 and before['registrationAllowed'] is False and before['resetPasswordAllowed']
        status,headers,_=kc.call(realm+'/users',{'username':username,'email':'kkk456miao@163.com',
            'emailVerified':True,'enabled':True,'firstName':username,'lastName':'MailTest',
            'credentials':[{'type':'password','value':password,'temporary':False}]},token)
        assert status==201;location=headers['Location']
        client=kc.browser()
        params={'client_id':'linesight-android','response_type':'code','redirect_uri':kc.redirect,
                'scope':'openid','state':secrets.token_urlsafe(24),
                'code_challenge':'a'*43,'code_challenge_method':'S256'}
        login=page(client,kc.issuer+'/protocol/openid-connect/auth?'+kc.urlencode(params))
        reset=next(u for u in login.links if '/login-actions/reset-credentials' in u)
        form=page(client,html.unescape(reset))
        anchor=receive_reset(username)
        page(client,html.unescape(next(iter(form.forms.values()))),{'username':username})
        parsed=Page();parsed.feed(receive_reset(username,anchor))
        link=next(html.unescape(u) for u in parsed.links if u.startswith(kc.issuer+'/login-actions/'))
        # Bind the received reset action to our disposable account before use.
        action_token=kc.parse_qs(kc.urlparse(link).query)['key'][0]
        encoded=action_token.split('.')[1]
        claims=json.loads(base64.urlsafe_b64decode(encoded+'='*((-len(encoded))%4)))
        assert claims['sub']==location.rsplit('/',1)[-1]
        change=page(client,link);assert 'password-new' in change.fields
        kc.open_form(client,html.unescape(change.forms['kc-passwd-update-form']),
                     {'password-new':replacement,'password-confirm':replacement})
        kc.authorize(kc.browser(),username,password,expect_denied=True)
        tokens=kc.authorize(kc.browser(),username,replacement);assert tokens['refresh_token']
        try:
            reused=page(kc.browser(),link);assert 'password-new' not in reused.fields
        except kc.HTTPError as error: assert error.code in (400,401,410)
        admin=admin_login();token=admin['access_token']
        status,_,after=kc.call(realm,token=token)
        assert status==200 and after['registrationAllowed'] is False and after['smtpServer']==before['smtpServer']
        result={'production_realm':'linesight','external_reset_email_received':True,
                'mail_transport':'Keycloak -> Postfix -> SMTP465 -> 163 mailbox',
                'reset_link_completed':True,'old_password_rejected':True,
                'new_password_pkce_login':True,'reset_link_reuse_rejected':True,
                'public_registration_closed':True,'existing_team_passwords_changed':False,
                'unrelated_mail_downloaded':False}
    finally:
        admin=admin_login();token=admin['access_token']
        if location: assert kc.call(location,token=token,method='DELETE')[0]==204
        kc.call(kc.origin+'/realms/master/protocol/openid-connect/logout',kc.urlencode({
            'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
    result['disposable_account_deleted']=True
    path=Path('docs/product/linesight/acceptance/mail57-batch/production-reset.json')
    path.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))


if __name__=='__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'passed':False,'type':type(error).__name__,
            'frames':[(Path(f.filename).name,f.lineno,f.name) for f in traceback.extract_tb(error.__traceback__)]}))
        raise SystemExit(1)
