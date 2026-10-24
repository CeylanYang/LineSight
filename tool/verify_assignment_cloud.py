"""Actual PKCE/HTTPS assignment, notification and issue-handover verification in isolated workspaces."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import secrets
import uuid
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request,urlopen
import verify_cloud_sessions as hosted

folder=Path('docs/product/linesight/acceptance/assignment-batch');folder.mkdir(parents=True,exist_ok=True)
def run():
    status,_,admin=hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/token',urlencode({
        'client_id':'admin-cli','grant_type':'password','username':hosted.private['KEYCLOAK_ADMIN_USERNAME'],'password':hosted.private['KEYCLOAK_ADMIN_PASSWORD']}).encode())
    assert status==200,'Provider administrator login failed'
    admin_api=hosted.origin+'/admin/realms/linesight/users'
    identities=[];tokens=[];result={}
    def call(actor,method,path,body=None,key=None):
        headers={'Authorization':'Bearer '+tokens[actor]['access_token'],'Content-Type':'application/json'}
        if key:headers['Idempotency-Key']=key
        try:
            with urlopen(Request(hosted.api+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method),timeout=25) as response:
                return response.status,json.load(response)
        except HTTPError as error:return error.code,json.load(error)
    def key():return 'assignment-'+uuid.uuid4().hex
    try:
        for role in ['owner','receiver']:
            username='assignment-'+role+'-'+uuid.uuid4().hex[:12];password=secrets.token_urlsafe(24)+'Aa7!'
            status,headers,_=hosted.call(admin_api,{'username':username,'enabled':True,'emailVerified':True,'firstName':'Assignment','lastName':role,
                'email':username+'@example.invalid','credentials':[{'type':'password','temporary':False,'value':password}]},admin['access_token'])
            assert status==201,'Temporary identity creation failed'
            identities.append(headers['Location'].rsplit('/',1)[1]);tokens.append(hosted.authorize(hosted.browser(),username,password))
        _,owner=call(0,'GET','auth/me/');_,receiver=call(1,'GET','auth/me/')
        base=f"workspaces/{owner['home_workspace_id']}/"
        status,invitation=call(0,'POST',base+'invite/',{'role':'operator'});assert status==201
        status,_=call(1,'POST','workspaces/redeem/',{'code':invitation['code']});assert status==201
        status,members=call(0,'GET',base+'members/');assert status==200 and all('active' in m for m in members)
        owner_id=next(m['id'] for m in members if m['is_self'])
        _,receiver_members=call(1,'GET',base+'members/')
        receiver_id=next(m['id'] for m in receiver_members if m['is_self'])
        status,job=call(0,'POST',base+'jobs/',{'part_name':'Assignment handover probe','printer':'A1','quantity':3,'assignee_id':owner_id},key());assert status==201
        path=base+f"jobs/{job['id']}/";assignment=path+'assignment/'
        payload={'version':1,'assignee_id':receiver_id,'note':''};first_key=key()
        status,first=call(0,'POST',assignment,payload,first_key);assert status==200 and first['version']==2
        _,notices=call(1,'GET',base+'notifications/');assert any(n['id']==job['id'] and not n['read'] for n in notices)
        status,_=call(1,'POST',base+f"notifications/{job['id']}/read/",{'version':2});assert status==200
        with ThreadPoolExecutor(max_workers=2) as pool:
            races=list(pool.map(lambda recipient:call(0,'POST',assignment,{'version':2,'assignee_id':recipient,'note':''},key()),[owner_id,None]))
        assert sorted(status for status,_ in races)==[200,409]
        latest=next(row for status,row in races if status==200)
        status,replay=call(0,'POST',assignment,payload,first_key);assert status==200 and replay==first
        status,_=call(0,'POST',assignment,{**payload,'assignee_id':None},first_key);assert status==409
        for target in ['printing','inspection']:
            status,latest=call(0,'PATCH',path,{'version':latest['version'],'status':target},key());assert status==200
        status,failed=call(0,'POST',path+'inspection/',{'version':latest['version'],'verdict':'fail','note':'Crack requiring repair','inspected_qty':3,'pass_qty':0,'fail_qty':3,'scrap_qty':0},key());assert status==201
        original=failed['inspections'][0];issue=failed['exceptions'][0]
        handoff={'version':failed['version'],'assignee_id':receiver_id,'note':'Continue the crack repair and attach completion evidence'}
        status,_=call(0,'POST',assignment,{**handoff,'note':''},key());assert status==400
        status,assigned=call(0,'POST',assignment,handoff,key());assert status==200
        assert assigned['exceptions'][0]['assignee']==receiver['display_name']
        assert assigned['inspections'][0]==original
        _,notices=call(1,'GET',base+'notifications/');assert any(n['id']==job['id'] and not n['read'] and n['version']==assigned['version'] for n in notices)
        _,old_notices=call(0,'GET',base+'notifications/');assert not any(n['id']==job['id'] for n in old_notices)
        status,_=call(0,'POST',assignment,{'version':assigned['version'],'assignee_id':2**63-1,'note':'Invalid reference'},key());assert status==400
        status,_=call(0,'POST',f"workspaces/{receiver['home_workspace_id']}/jobs/{job['id']}/assignment/",handoff,key());assert status==404
        status,resolved=call(1,'POST',base+f"exceptions/{issue['id']}/resolve/",{'version':assigned['version'],'resolution':'Crack repaired','next_status':'inspection'},key());assert status==200
        status,closed=call(1,'POST',path+'inspection/',{'version':resolved['job_version'],'verdict':'pass','note':'Repaired surface checked','inspected_qty':3,'pass_qty':3,'fail_qty':0,'scrap_qty':0},key());assert status==201
        assert len(closed['inspections'])==2 and closed['status']=='closed'
        status,_=call(0,'POST',assignment,{'version':closed['version'],'assignee_id':owner_id,'note':''},key());assert status==409
        _,history=call(0,'GET',path+'history/')
        assignments=[e for e in history if e['action']=='job.assigned'];assert len(assignments)==3
        assert assignments[-1]['details']['note']==handoff['note'] and assignments[-1]['details']['handed_over_issues'][0]['id']==issue['id']
        (folder/'live-assignment-fixture.json').write_text(json.dumps({'workspace_id':owner['home_workspace_id'],'before_handoff':failed,'assigned':assigned,'closed':closed,'history':history},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        result={'passed':True,'native_pkce_provider_flow':True,'new_isolated_workspaces':2,'new_probe_tasks':1,
            'assignment_notification_read_and_reassignment':True,'concurrent_one_success_one_conflict':True,
            'receipt_replay_and_mismatched_key_rejected':True,'issue_handoff_note_required':True,'handoff_keeps_original_inspection':True,
            'previous_recipient_notice_removed':True,'new_recipient_notice_unread':True,'foreign_workspace_and_recipient_rejected':True,
            'receiver_completes_repair_and_reinspection':True,'closed_assignment_rejected':True,'versioned_handover_history':True,
            'existing_user_data_modified':False}
    finally:
        for token in tokens:hosted.call(hosted.issuer+'/protocol/openid-connect/logout',urlencode({'client_id':'linesight-android','refresh_token':token['refresh_token']}).encode())
        for subject in identities:assert hosted.call(admin_api+'/'+subject,token=admin['access_token'],method='DELETE')[0]==204
        hosted.call(hosted.origin+'/realms/master/protocol/openid-connect/logout',urlencode({'client_id':'admin-cli','refresh_token':admin['refresh_token']}).encode())
    result['temporary_provider_identities_deleted']=True
    (folder/'live-assignment.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
if __name__=='__main__':run()
