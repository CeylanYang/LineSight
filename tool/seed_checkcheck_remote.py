"""Initialize only the requested team; config is injected by the local operator.

Business commands generate real state-machine records. Imported historical
times carry an internal origin marker and never fabricate security login logs.
"""
import json,os,shlex,sys
from pathlib import Path
import pysqlite3 as sqlite3
sys.modules['sqlite3']=sqlite3
for line in Path('/etc/linesight/linesight.env').read_text().splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        key,value=line.split('=',1);os.environ[key.strip()]=' '.join(shlex.split(value))
os.environ['DJANGO_SETTINGS_MODULE']='linesight.production_settings'
sys.path.insert(0,'/opt/linesight/backend')
import django
django.setup()
from django.conf import settings
from django.db import transaction
from django.utils import timezone
from datetime import timedelta
from rest_framework.test import APIClient
from collaboration.models import CloudIdentity,Workspace,Membership,ProductionJob,QualityInspection,AuditEvent,ExceptionCase

batch='checkcheck-20261024-v1'
state=Path('/var/lib/linesight/initializations')/(batch+'.json')
state.parent.mkdir(exist_ok=True,mode=0o700)
if state.exists():
    print(state.read_text());raise SystemExit(0)
anchor=timezone.now()
backup=Path('/var/backups/linesight/team53')/(anchor.strftime('%Y%m%dT%H%M%SZ')+'-before-seed')
backup.mkdir(mode=0o700,parents=True)
with sqlite3.connect(str(settings.DATABASES['default']['NAME'])) as source,sqlite3.connect(str(backup/'linesight.sqlite3')) as target:source.backup(target)
os.chmod(backup/'linesight.sqlite3',0o600)
identities=[CloudIdentity.objects.select_related('user').get(subject=row['subject'],issuer=config['issuer']) for row in config['members']]
assert len({i.pk for i in identities})==12 and all(not i.is_demo for i in identities)
clients=[]
for identity in identities:
    client=APIClient();client.force_authenticate(identity.user,token={'iss':config['issuer'],'iat':anchor.timestamp(),'is_demo':False,'preferred_username':identity.user.username});clients.append(client)

def request(actor,method,path,body=None,key=None):
    args={'format':'json','secure':True,'HTTP_HOST':'47.111.81.94'}
    if key:args['HTTP_IDEMPOTENCY_KEY']=key
    response=getattr(clients[actor],method.lower())('/api/v1/'+path,body,**args)
    assert response.status_code in (200,201,204),(method,path,response.status_code,response.data)
    return response.data

with transaction.atomic():
    ws=Workspace.objects.create(name='checkcheck',kind='team');base=f'workspaces/{ws.pk}/'
    for identity,row in zip(identities,config['members']):
        Membership.objects.create(workspace=ws,user=identity.user,role=row['role'])
        for field in ('display_name','avatar_seed','job_title'):setattr(identity,field,row[field])
        identity.home_workspace=ws;identity.save(update_fields=['display_name','avatar_seed','job_title','home_workspace'])
        AuditEvent.objects.create(workspace=ws,user=identities[0].user,action='member.joined',object_id=str(identity.user_id),details={'role':row['role'],'data_origin':'team_initialization','initialization_batch':batch})
    labels=[['关键尺寸','表面外观','装配配合'],['孔位与孔径','连接面平整度','紧固配合'],['外形完整性','倒角与毛刺','批次标识']]
    templates=[]
    for index,name in enumerate(['尺寸与装配检验','支架与连接件检验','外观与标识检验']):
        templates.append(request(1 if index!=2 else 2,'POST',base+'templates/',{'name':name,'items':[{'id':f'item-{n}','label':label,'required':True,'allow_na':False} for n,label in enumerate(labels[index])]},f'checkcheck-template-{index:04d}'))
    printers=['Bambu Lab A1 · 01号工位','Bambu Lab P2S · 02号工位','Bambu Lab X1C · 03号工位'];profiles=[]
    for index,name in enumerate(printers):
        profiles.append(request(1,'POST',base+'printer-profiles/',{'name':name,'version':'2026.10','source':'https://bambulab.com/en/'+['a1','p2s','x1-carbon'][index],'note':['PLA / 0.20 mm / 210 °C','PETG / 0.20 mm / 245 °C','ABS / 0.16 mm / 255 °C'][index],'default_template_id':templates[index]['id']},f'checkcheck-printer-{index:04d}'))
    parts=['伺服电机安装支架','光电传感器固定座','输送线导向块','定位工装连接板','气缸限位挡块','设备线缆固定夹','相机调节支座','轴承座防护盖','夹具定位销座','模组快换接头','测量治具底座','小型壳体端盖'];jobs=[]
    for i in range(24):
        actor=i%12;inspector=(i+3)%12;template=templates[i%3];qty=[12,18,24,8,16,20][i%6]
        serials=[f'CC-2610-{i+1:03d}-{n+1:03d}' for n in range(qty)] if i%4==0 else []
        body={'part_name':parts[i%12]+(' · A批' if i<12 else ' · B批'),'printer':printers[i%3],'profile_id':profiles[i%3]['id'],'quantity':qty,'batch_code':f'CC-2610-{i+1:03d}','assignee_id':identities[actor].user_id,'template_id':template['id'],'tracking_mode':'serial' if serials else 'batch','serial_numbers':serials,'note':['按工艺卡 CC-OP-03 执行，重点检查装配面。','交接前确认孔位与标识，记录关键尺寸。','使用对应版本检查清单，完工后送检。'][i%3]}
        job=request(actor,'POST',base+'jobs/',body,f'checkcheck-job-{i+1:04d}');path=base+f"jobs/{job['id']}/";step=0
        def mutate(who,method,suffix,payload):
            global step,job
            step+=1
            job=request(who,method,path+suffix,{'version':job['version'],**payload},f'checkcheck-{i+1:03d}-step-{step:03d}')
        def inspect(verdict,who):
            fail=verdict=='fail';finding=['安装孔中心距超出工艺公差，需修整定位面。','边缘有毛刺，影响贴合，需清理并复核。','局部装配间隙偏紧，需调整配合面。'][i%3]
            answers=[{'id':item['id'],'result':'fail' if fail and n==0 else 'pass','note':finding if fail and n==0 else ''} for n,item in enumerate(template['items'])]
            mutate(who,'POST','inspection/',{'verdict':verdict,'note':finding if fail else '关键尺寸、外观及装配检查通过，批次标识齐全。','inspected_qty':qty,'pass_qty':qty-1 if fail else qty,'fail_qty':1 if fail else 0,'scrap_qty':0,'answers':answers,'serial_results':{s:('fail' if fail and n==0 else 'pass') for n,s in enumerate(serials)},'category':['dimension','surface','assembly'][i%3],'severity':'major' if i%3!=1 else 'minor'})
        target='closed' if i<12 else 'inspection' if i<16 else 'exception' if i<19 else 'printing' if i<22 else 'queued'
        if target!='queued':mutate(actor,'PATCH','',{'status':'printing'})
        if target not in ('queued','printing'):mutate(actor,'PATCH','',{'status':'inspection'})
        needs_rework=(i<12 and i%4==0) or i in (12,13) or target=='exception'
        if needs_rework:
            inspect('fail',inspector)
            mutate(1 if i%2==0 else 2,'POST','assignment/',{'assignee_id':identities[(i+5)%12].user_id,'note':'已移交返修工位，请按异常项修整并保留复检结果。'})
            if target!='exception':
                case=next(c for c in job['exceptions'] if c['status']=='open')
                request(1 if i%2==0 else 2,'POST',base+f"exceptions/{case['id']}/resolve/",{'version':job['version'],'resolution':'完成定位面修整与边缘清理，重新确认装配配合，提交独立复检。','next_status':'inspection'},f'checkcheck-resolve-{i+1:04d}')
                job=request(actor,'GET',path)
        if target=='closed':inspect('pass',(i+6)%12 if needs_rework else inspector)
        assert job['status']==target,(i,job['status'],target)
        task=ProductionJob.objects.get(pk=job['id']);start=anchor-timedelta(days=(i%6),hours=5) if i<12 else anchor-timedelta(hours=3+i%3)
        events=list(task.events.order_by('pk'))
        for n,event in enumerate(events):
            at=start+timedelta(minutes=9*n);event.created_at=at
            event.details={**event.details,'data_origin':'team_initialization','initialization_batch':batch,'initialized_at':anchor.isoformat()};event.save(update_fields=['created_at','details'])
            if event.action.startswith('inspection.'):QualityInspection.objects.filter(pk=event.object_id,job=task).update(created_at=at)
            if event.action.startswith('exception.resolved'):ExceptionCase.objects.filter(pk=event.object_id,job=task).update(resolved_at=at)
        for case in task.exceptions.select_related('inspection'):
            ExceptionCase.objects.filter(pk=case.pk).update(created_at=case.inspection.created_at if case.inspection else start)
        ProductionJob.objects.filter(pk=task.pk).update(created_at=start,updated_at=start+timedelta(minutes=max(1,len(events)-1)*9));jobs.append(str(task.pk))
    invitations=[request(0,'POST',base+'invite/',{'role':role}) for role in ['operator','operator','operator','manager','viewer']]
    summary=request(0,'GET',base+'metrics/')
    assert summary['task_counts']=={'queued':2,'printing':3,'inspection':4,'exception':3,'closed':12}
    assert Membership.objects.filter(workspace=ws).count()==12
    result={'workspace_id':ws.pk,'team_name':ws.name,'members':12,'roles':{'owner':1,'manager':2,'operator':9},'tasks':24,'checks':QualityInspection.objects.filter(job__workspace=ws).count(),'audit_events':AuditEvent.objects.filter(workspace=ws).count(),'task_counts':summary['task_counts'],'templates':3,'printer_profiles':3,'internal_data_origin':'team_initialization','invitations_private':invitations,'backup':str(backup),'jobs':jobs}
state.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');os.chmod(state,0o600)
print(json.dumps(result,ensure_ascii=False))
