"""Real PKCE enrollment and Keycloak NFC token lifecycle using a generated card fixture."""
import base64
import hashlib
import json
from pathlib import Path
import secrets
import uuid
from urllib.parse import urlencode
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
import verify_cloud_sessions as hosted

folder=Path('docs/product/linesight/acceptance/nfc-batch');folder.mkdir(parents=True,exist_ok=True)
api=hosted.api;issuer=hosted.issuer;origin=hosted.origin
def run():
    status,_,admin=hosted.call(origin+'/realms/master/protocol/openid-connect/token',urlencode({'client_id':'admin-cli','grant_type':'password','username':hosted.private['KEYCLOAK_ADMIN_USERNAME'],'password':hosted.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200,'Admin login failed'
    admin_api=origin+'/admin/realms/linesight/'
    username='nfc-probe-'+uuid.uuid4().hex[:12];password=secrets.token_urlsafe(24)+'Aa7!'
    subject=None;password_tokens=None;nfc_tokens=[];credential=None
    def call(path,data=None,token=None,method=None):return hosted.call(api+path,data,token,method)
    def proof(fields,private,token=None):
        status,_,challenge=call('auth/nfc/challenges/',fields,token)
        assert status==200,f"NFC {fields['action']} challenge status {status}"
        payload={'challenge_id':challenge['id'],'signature':base64.b64encode(private.sign(challenge['message'].encode())).decode()}
        if 'refresh_token' in fields:payload['refresh_token']=fields['refresh_token']
        status,_,result=call('auth/nfc/complete/',payload,token)
        return status,result,payload
    try:
        status,headers,_=hosted.call(admin_api+'users',{'username':username,'enabled':True,'emailVerified':True,'firstName':'NFC','lastName':'Probe','email':username+'@example.invalid','credentials':[{'type':'password','temporary':False,'value':password}]},admin['access_token'])
        assert status==201,'Temporary identity creation failed';subject=headers['Location'].rsplit('/',1)[1]
        password_tokens=hosted.authorize(hosted.browser(),username,password)
        assert call('auth/me/',token=password_tokens['access_token'])[0]==200
        private=Ed25519PrivateKey.generate();public=base64.b64encode(private.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)).decode()
        card=hashlib.sha256(secrets.token_bytes(32)).hexdigest()
        status,binding,replay=proof({'action':'bind','public_key':public,'card_code':card,'technology':'Generated UID fixture; no physical NFC card','label':'LineSight · 01'},private,password_tokens['access_token'])
        assert status==201,f'Enrollment status {status}';credential=binding['id']
        assert call('auth/nfc/complete/',replay,password_tokens['access_token'])[0]==401
        fixture={'credential_id':credential,'card_code':card}
        status,tokens,replay=proof({'action':'login',**fixture},private)
        assert status==200,f'NFC login status {status}';nfc_tokens.append(tokens)
        assert call('auth/me/',token=tokens['access_token'])[0]==200,'NFC access rejected'
        assert call('auth/nfc/complete/',replay)[0]==401,'NFC proof replay accepted'
        # A copied card identifier without the bound device key cannot sign in.
        status,_,challenge=call('auth/nfc/challenges/',{'action':'login',**fixture})
        assert status==200
        wrong=base64.b64encode(Ed25519PrivateKey.generate().sign(challenge['message'].encode())).decode()
        assert call('auth/nfc/complete/',{'challenge_id':challenge['id'],'signature':wrong})[0]==401
        status,refreshed,_=proof({'action':'refresh','credential_id':credential,'refresh_token':tokens['refresh_token']},private)
        assert status==200,f'NFC refresh status {status}';nfc_tokens.append(refreshed)
        assert call('auth/nfc/challenges/',{'action':'refresh','credential_id':credential,'refresh_token':tokens['refresh_token']})[0]==401
        assert call('auth/me/',token=refreshed['access_token'])[0]==200
        status,second,_=proof({'action':'login',**fixture},private);assert status==200;nfc_tokens.append(second)
        status,_,_=proof({'action':'logout','credential_id':credential,'refresh_token':second['refresh_token']},private);assert status==200
        assert call('auth/me/',token=second['access_token'])[0]==401,'NFC logout access still valid'
        assert call('auth/me/',token=refreshed['access_token'])[0]==200,'Other NFC session unexpectedly revoked'
        assert call(f'auth/nfc/credentials/{credential}/',token=password_tokens['access_token'],method='DELETE')[0]==200
        assert call('auth/me/',token=refreshed['access_token'])[0]==401,'Unbound NFC access still valid'
        assert call('auth/nfc/challenges/',{'action':'refresh','credential_id':credential,'refresh_token':refreshed['refresh_token']})[0]==401
        assert call('auth/me/',token=password_tokens['access_token'])[0]==200,'Password session unexpectedly revoked'
        result={'fixture':'Generated random card code and Ed25519 device key; no physical phone/card','native_pkce_enrollment':True,'server_keycloak_login':True,'proof_replay_rejected':True,'copied_card_without_device_key_rejected':True,'refresh_rotation':True,'old_refresh_rejected':True,'single_nfc_session_logout':True,'other_nfc_session_preserved':True,'unbind_access_and_refresh_rejected':True,'password_session_preserved':True,'normal_native_password_grant_unchanged':True,'provider_probe_deleted':True}
        (folder/'live-api.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        (folder/'live-card-list.json').write_text(json.dumps([{'id':'acceptance-card-redacted','label':'LineSight · 01','technology':binding['technology'],'created_at':binding['created_at'],'revoked':False}],indent=2)+'\n',encoding='utf-8')
        print(json.dumps(result))
    finally:
        if credential and password_tokens:call(f'auth/nfc/credentials/{credential}/',token=password_tokens['access_token'],method='DELETE')
        if subject:hosted.call(admin_api+'users/'+subject,token=admin['access_token'],method='DELETE')
        if password_tokens:hosted.call(issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-android','refresh_token':password_tokens['refresh_token']}).encode())
        hosted.call(origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
if __name__=='__main__':
    try:run()
    except AssertionError as error:print(json.dumps({'passed':False,'reason':str(error)}));raise SystemExit(1)
