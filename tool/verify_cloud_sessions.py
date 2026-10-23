"""Verify hosted password change and official Keycloak session APIs on a disposable user."""
import base64
import hashlib
import html
from html.parser import HTMLParser
from http.cookiejar import CookieJar
import json
from pathlib import Path
import secrets
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse, parse_qs
from urllib.request import Request, build_opener, HTTPCookieProcessor, HTTPRedirectHandler, urlopen
import uuid
import traceback

config=json.loads(Path('.artifact-work/sso/demo-build.json').read_text(encoding='utf-8-sig'))
private=dict(line.split('=',1) for line in Path('.artifact-work/sso/identity.env').read_text().splitlines() if '=' in line)
issuer=config['LINESIGHT_OIDC_ISSUER']; origin=issuer.split('/realms/')[0]
api=config['LINESIGHT_API_BASE_URL']; redirect='com.linesight.app:/oauthredirect'
folder=Path('docs/product/linesight/acceptance/session-batch'); folder.mkdir(parents=True,exist_ok=True)

def call(url,data=None,token=None,method=None):
    headers={'Accept':'application/json'}
    if token: headers['Authorization']='Bearer '+token
    if isinstance(data,dict): headers['Content-Type']='application/json'; data=json.dumps(data).encode()
    elif data is not None: headers['Content-Type']='application/x-www-form-urlencoded'
    try:
        with urlopen(Request(url,data=data,headers=headers,method=method),timeout=20) as response:
            raw=response.read(); return response.status,response.headers,json.loads(raw) if raw else None
    except HTTPError as error:
        return error.code,error.headers,None

def grant(fields): return call(issuer+'/protocol/openid-connect/token',urlencode(fields).encode())
class NativeRedirect(HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        if newurl.startswith('com.linesight.app:'): return None
        return super().redirect_request(req,fp,code,msg,headers,newurl)
class Form(HTMLParser):
    def __init__(self): super().__init__(); self.forms={}; self.current=None; self.fields=[]
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=='form': self.current=attrs.get('id',''); self.forms[self.current]=attrs.get('action','')
        if tag=='input' and attrs.get('name'): self.fields.append(attrs['name'])

def browser(): return build_opener(HTTPCookieProcessor(CookieJar()),NativeRedirect())
def open_form(client,url,data=None):
    try:
        with client.open(Request(url,data=urlencode(data).encode() if data is not None else None),timeout=20) as response:
            form=Form(); form.feed(response.read().decode()); return form,None
    except HTTPError as error:
        if error.code==302 and error.headers.get('Location','').startswith('com.linesight.app:'):
            return None,parse_qs(urlparse(error.headers['Location']).query)
        raise RuntimeError('Unexpected provider browser response') from None

def authorize(client,username,password,change=False,new_password=None,expect_denied=False):
    verifier=secrets.token_urlsafe(48); state=secrets.token_urlsafe(24)
    challenge=base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
    params={'client_id':'linesight-android','response_type':'code','redirect_uri':redirect,
        'scope':'openid profile email','state':state,'code_challenge':challenge,'code_challenge_method':'S256'}
    if change: params['kc_action']='UPDATE_PASSWORD'
    form,result=open_form(client,issuer+'/protocol/openid-connect/auth?'+urlencode(params))
    if form and 'kc-form-login' in form.forms:
        form,result=open_form(client,html.unescape(form.forms['kc-form-login']),{'username':username,'password':password})
    if expect_denied:
        assert result is None and form and 'kc-form-login' in form.forms,'Old password was not rejected'
        return None
    if change:
        assert form and 'kc-passwd-update-form' in form.forms, 'Hosted update form missing'
        assert 'logout-sessions' in form.fields, 'Provider logout control missing'
        form,result=open_form(client,html.unescape(form.forms['kc-passwd-update-form']),{
            'password-new':new_password,'password-confirm':new_password,'logout-sessions':'on'})
    assert result and result.get('state')==[state] and 'code' in result,'Native authorization did not complete'
    status,_,tokens=grant({'grant_type':'authorization_code','client_id':'linesight-android',
        'code':result['code'][0],'redirect_uri':redirect,'code_verifier':verifier})
    assert status==200,'PKCE exchange failed'
    return tokens

def inactive(tokens):
    assert call(api+'auth/me/',token=tokens['access_token'])[0]==401,'Revoked API token accepted'
    assert grant({'grant_type':'refresh_token','client_id':'linesight-android','refresh_token':tokens['refresh_token']})[0]==400,'Revoked refresh accepted'

def run():
    status,_,admin=call(origin+'/realms/master/protocol/openid-connect/token',urlencode({
        'client_id':'admin-cli','grant_type':'password','username':private['KEYCLOAK_ADMIN_USERNAME'],'password':private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200,'Admin authentication failed'
    token=admin['access_token']; location=None; demo=None
    result={}
    try:
        status,_,realm=call(origin+'/admin/realms/linesight',token=token); assert status==200
        result['reset_password_enabled']=realm.get('resetPasswordAllowed',False)
        result['smtp_configured']=bool(realm.get('smtpServer',{}).get('host'))
        username='session-probe-'+uuid.uuid4().hex; password=secrets.token_urlsafe(32); new_password=secrets.token_urlsafe(32)
        status,headers,_=call(origin+'/admin/realms/linesight/users',{'username':username,'enabled':True,
            'firstName':'Session','lastName':'Probe','email':username+'@example.invalid',
            'credentials':[{'type':'password','value':password,'temporary':False}]},token)
        assert status==201; location=headers['Location']
        first=authorize(browser(),username,password); second_browser=browser(); second=authorize(second_browser,username,password)
        endpoint=issuer+'/account/sessions'
        status,_,sessions=call(endpoint,token=second['access_token']); assert status==200 and len(sessions)==2
        assert sum(bool(s.get('current')) for s in sessions)==1
        # Omit IP/session identifiers from the public visual fixture.
        fixture=[{k:v for k,v in row.items() if k in ['current','started','lastAccess','expires','browser','clients']} for row in sessions]
        (folder/'live-sessions.json').write_text(json.dumps({'origin':'Actual HTTPS sessions for disposable acceptance user; IPs and identifiers omitted','sessions':fixture},indent=2)+'\n',encoding='utf-8')
        result['native_pkce_two_independent_sessions']=True
        second=authorize(second_browser,username,password,change=True,new_password=new_password)
        inactive(first); result['hosted_password_change_revoked_old_session']=True
        authorize(browser(),username,password,expect_denied=True); result['old_password_rejected']=True
        third=authorize(browser(),username,new_password); result['new_password_native_login']=True
        status,_,sessions=call(endpoint,token=second['access_token']); assert status==200
        other=next(s for s in sessions if not s.get('current'))
        status,_,demo=grant({'client_id':'linesight-demo','grant_type':'password','username':config['LINESIGHT_DEMO_USERNAME'],'password':config['LINESIGHT_DEMO_PASSWORD']}); assert status==200
        foreign_status=call(endpoint+'/'+other['id'],token=demo['access_token'],method='DELETE')[0]
        assert foreign_status in (204,400,401,403,404),f'Unexpected cross-user response {foreign_status}'
        assert call(api+'auth/me/',token=third['access_token'])[0]==200
        result['cross_user_session_id_cannot_revoke']=True
        result['cross_user_session_response_status']=foreign_status
        deletion_status=call(endpoint+'/'+other['id'],token=second['access_token'],method='DELETE')[0]
        assert deletion_status==204,f'Session deletion response {deletion_status}'
        inactive(third); result['specific_session_access_and_refresh_revoked']=True
        fourth=authorize(browser(),username,new_password)
        assert call(endpoint+'?current=false',token=second['access_token'],method='DELETE')[0]==204
        inactive(fourth)
        status,_,remaining=call(endpoint,token=second['access_token']); assert status==200 and len(remaining)==1 and remaining[0]['current']
        result['logout_other_sessions_keeps_current']=True
        assert call(api+'auth/me/',token=second['access_token'])[0]==200
        assert call(issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-android','refresh_token':second['refresh_token']}).encode())[0] in (200,204)
        inactive(second); result['current_logout_revokes_access_and_refresh']=True
    finally:
        if demo: call(issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-demo','refresh_token':demo['refresh_token']}).encode())
        if location:
            assert call(location,token=token,method='DELETE')[0]==204,'Probe cleanup failed'
            result['provider_probe_deleted']=True
        call(origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
    result['production_or_demo_passwords_changed']=False
    result['normal_client_password_grant_enabled']=False
    (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':
    try: run()
    except Exception as error:
        print(json.dumps({'passed':False,'failure_type':type(error).__name__,'failure_line':traceback.extract_tb(error.__traceback__)[-1].lineno,'reason':str(error) if isinstance(error,AssertionError) else 'Provider verification interrupted'}))
        raise SystemExit(1)
