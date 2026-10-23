"""Host-side Keycloak SPI rollout with existing complete backup and config rollback."""
import datetime
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import urlencode,quote
from urllib.request import Request,urlopen

root=Path('/opt/linesight-identity')
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup=Path('/var/backups/linesight/identity')/('nfc-'+stamp);backup.mkdir(mode=0o700)
subprocess.run(['systemctl','start','linesight-cloud-backup.service'],check=True)
for name in ['compose.yaml','identity.env']:shutil.copy2(root/name,backup/name)
shutil.copy2('/etc/linesight/linesight.env',backup/'linesight.env')
private=dict(line.split('=',1) for line in (root/'identity.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
ticket=private.get('LINESIGHT_NFC_TICKET_SECRET') or secrets.token_urlsafe(48)
def append_env(path,values):
    lines=[line for line in path.read_text().splitlines() if line.split('=',1)[0] not in values]
    path.write_text('\n'.join(lines)+'\n'+''.join(f'{key}={value}\n' for key,value in values.items()))

compose=[str(root/'tools/bin/podman-compose'),'--env-file','identity.env']
def recreate():subprocess.run([*compose,'up','-d','--no-deps','--force-recreate','keycloak'],cwd=root,check=True)
issuer='https://47.111.81.94/sso/realms/linesight'
def ready():
    for attempt in range(100):
        try:
            with urlopen(issuer+'/.well-known/openid-configuration',timeout=3) as response:
                if json.load(response)['issuer']==issuer:return
        except Exception:time.sleep(1)
    raise RuntimeError('Identity discovery failed')

try:
    providers=root/'providers';providers.mkdir(exist_ok=True)
    shutil.copy2(root/'api-cutover/linesight-nfc-provider.jar',providers/'linesight-nfc-provider.jar')
    os.chmod(providers/'linesight-nfc-provider.jar',0o644)
    append_env(root/'identity.env',{'LINESIGHT_NFC_TICKET_SECRET':ticket})
    config=(root/'compose.yaml').read_text()
    if 'LINESIGHT_NFC_TICKET_SECRET:' not in config:
        config=config.replace('      KC_DB: postgres','      LINESIGHT_NFC_TICKET_SECRET: ${LINESIGHT_NFC_TICKET_SECRET:?Generate NFC ticket key}\n      KC_DB: postgres')
    if './providers:' not in config:
        config=config.replace('      - ./realm:/opt/keycloak/data/import:ro,Z','      - ./realm:/opt/keycloak/data/import:ro,Z\n      - ./providers:/opt/keycloak/providers:ro,Z')
    (root/'compose.yaml').write_text(config)
    recreate();ready()
    master='https://47.111.81.94/sso/realms/master/protocol/openid-connect/token'
    with urlopen(Request(master,data=urlencode({'client_id':'admin-cli','grant_type':'password','username':private['KEYCLOAK_ADMIN_USERNAME'],'password':private['KEYCLOAK_ADMIN_PASSWORD']}).encode()),timeout=15) as response:
        admin=json.load(response)
    api='https://47.111.81.94/sso/admin/realms/linesight/'
    def call(path,data=None,method=None):
        headers={'Authorization':'Bearer '+admin['access_token'],'Content-Type':'application/json'}
        with urlopen(Request(api+path,data=json.dumps(data).encode() if data is not None else None,headers=headers,method=method),timeout=20) as response:
            raw=response.read();return json.loads(raw) if raw else None
    flow=next((row for row in call('authentication/flows') if row['alias']=='linesight-nfc-device'),None)
    if flow is None:
        call('authentication/flows',{'alias':'linesight-nfc-device','description':'Server-verified NFC and device signature','providerId':'basic-flow','topLevel':True,'builtIn':False})
        flow=next(row for row in call('authentication/flows') if row['alias']=='linesight-nfc-device')
    executions=call('authentication/flows/linesight-nfc-device/executions')
    if not any(row.get('providerId')=='linesight-nfc-ticket' for row in executions):
        call('authentication/flows/linesight-nfc-device/executions/execution',{'provider':'linesight-nfc-ticket'})
    for execution in call('authentication/flows/linesight-nfc-device/executions'):
        if execution.get('providerId')=='linesight-nfc-ticket':
            execution['requirement']='REQUIRED';call('authentication/flows/linesight-nfc-device/executions',execution,'PUT')
    native=call('clients?clientId=linesight-android')[0]
    native=call('clients/'+native['id'])
    existing=call('clients?clientId=linesight-nfc')
    client={'clientId':'linesight-nfc','name':'LineSight NFC','enabled':True,'protocol':'openid-connect','publicClient':False,
        'standardFlowEnabled':False,'directAccessGrantsEnabled':True,'serviceAccountsEnabled':False,'implicitFlowEnabled':False,
        'fullScopeAllowed':True,'defaultClientScopes':native.get('defaultClientScopes',[]),'optionalClientScopes':native.get('optionalClientScopes',[]),
        'authenticationFlowBindingOverrides':{'direct_grant':flow['id']},
        'protocolMappers':[{'name':'nfc-binding','protocol':'openid-connect','protocolMapper':'oidc-usersessionmodel-note-mapper','config':{'user.session.note':'nfc_binding','claim.name':'nfc_binding','jsonType.label':'String','access.token.claim':'true','id.token.claim':'true','userinfo.token.claim':'false'}},
            {'name':'linesight-api-audience','protocol':'openid-connect','protocolMapper':'oidc-audience-mapper','config':{'included.client.audience':'linesight-api','access.token.claim':'true','id.token.claim':'false'}}]}
    if existing:
        client['id']=existing[0]['id'];call('clients/'+client['id'],client,'PUT')
    else:
        call('clients',client);client=call('clients?clientId=linesight-nfc')[0]
    client_secret=call('clients/'+client['id']+'/client-secret')['value']
    append_env(Path('/etc/linesight/linesight.env'),{'LINESIGHT_NFC_TICKET_SECRET':ticket,'LINESIGHT_NFC_CLIENT_SECRET':client_secret})
    os.chmod('/etc/linesight/linesight.env',0o640)
    subprocess.run(['chown','root:linesight','/etc/linesight/linesight.env'],check=True)
    # Verify the new client cannot bypass the SPI using a normal password grant.
    try:
        urlopen(Request(issuer+'/protocol/openid-connect/token',data=urlencode({'client_id':'linesight-nfc','client_secret':client_secret,'grant_type':'password','username':'nfc','password':'not-a-credential'}).encode()),timeout=15)
        raise AssertionError('NFC client accepted password without server assertion')
    except HTTPError as error:assert error.code==400
    subprocess.run(['systemctl','restart','linesight'],check=True)
    report={'backup':str(backup),'provider':'Keycloak 26.8.1 Authenticator SPI','flow':'linesight-nfc-device','confidential_client':'linesight-nfc','password_without_assertion_rejected':True,'discovery_ready':True,'normal_native_client_unchanged':True}
    (backup/'deployment.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))
except BaseException:
    for name in ['compose.yaml','identity.env']:shutil.copy2(backup/name,root/name)
    shutil.copy2(backup/'linesight.env','/etc/linesight/linesight.env')
    recreate();ready();subprocess.run(['systemctl','restart','linesight'],check=True)
    print('NFC identity rollout failed; previous runtime configuration restored.')
    raise
