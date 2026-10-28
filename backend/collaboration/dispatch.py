from datetime import datetime, time
from zoneinfo import ZoneInfo
import random
import re
from django.db import transaction
from django.db.models import F
from .models import Workspace, WorkspaceBulletin, ProductionJob, CheckTemplate, AuditEvent

SLOTS = {9: 7, 12: 6, 18: 7}
ZONE = ZoneInfo('Asia/Shanghai')
PARTS = ['伺服电机安装支架', '相机调节支座', '定位工装连接板', '输送线导向块', '传感器固定座', '模组快换接头', '壳体端盖', '线缆固定夹']
NOTICES = [
 ('班前点检安排', '{line}号工位请在{hour}:30前完成量具归位与光源确认，抽检{samples}件，记录批次{batch}。'),
 ('物料交接预告', '批次{batch}预计进入{line}号工位，本轮计划{qty}件；交接时核对包装标签与工艺卡。'),
 ('质量例会提醒', '今日{hour}:40召开工位协调会，请整理{samples}项检查要点，重点关注{part}的装配面。'),
 ('设备养护窗口', '{line}号设备将在本班结束后进行例行养护，请提前完成{qty}件在制品的标识与归位。'),
 ('工艺参数复核', '{part}本轮建议抽查{samples}件，重点复核孔位、毛刺与贴合面，记录到批次{batch}。'),
 ('发运准备通知', '批次{batch}纳入下一轮发运准备，预计整理{qty}件。请按工位清单检查标识与交接单。'),
 ('换型检查预告', '{line}号工位下一轮切换至{part}，准备{samples}项换型核对内容，并确认治具归位。'),
]

def render(text, values):
    return re.sub(r'\{([a-z]+)\}', lambda m: str(values[m[1]]), text)

@transaction.atomic
def dispatch(workspace_id, day, slot):
    if slot not in SLOTS:
        raise ValueError('unsupported slot')
    Workspace.objects.filter(pk=workspace_id).update(name=F('name'))
    workspace = Workspace.objects.select_for_update().get(pk=workspace_id)
    if not workspace.dispatch_enabled:
        raise ValueError('workspace scheduling is disabled')
    key = f'dispatch/{workspace.pk}/{day.isoformat()}/{slot}'
    if WorkspaceBulletin.objects.filter(source_key=key+'/0').exists():
        return 0
    at = datetime.combine(day, time(slot), ZONE)
    rng = random.Random(key)
    made = 0
    jobs = []
    job_batches = []
    for i in range(SLOTS[slot]):
        part = PARTS[rng.randrange(len(PARTS))]
        values = dict(line=rng.randint(1,6), hour=slot, samples=rng.randint(3,8), qty=rng.choice([12,18,24,32,48,60]), batch=f'CC-{day:%y%m%d}-{slot:02d}{i+1:02d}',part=part)
        job = template = None
        if i < 2:
            kind = 'task'
            title = f'{part} · {values["batch"]}'
            body = render('本轮安排{qty}件{part}，使用{line}号工位。开工前核对批次{batch}，首轮抽查{samples}件后进入常规巡检。', values)
            job = ProductionJob.objects.create(workspace=workspace,part_name=part,printer=f'{values["line"]}号工位',quantity=values['qty'],batch_code=values['batch'],note=body,status='queued')
            jobs.append(job.pk)
            job_batches.append(job.batch_code)
            ProductionJob.objects.filter(pk=job.pk).update(created_at=at,updated_at=at)
            AuditEvent.objects.create(workspace=workspace,job=job,version=1,action='job.created',object_id=str(job.pk),details={'data_origin':'scheduled_demo','schedule_key':key,'scheduled_at':at.isoformat()})
        elif i == 2:
            kind = 'template'
            title = f'生产巡检 · {day:%Y年%m月%d日}{slot}时检查清单'
            body = render('本轮检查清单已整理，覆盖外观、装配与批次标识。建议首轮抽查{samples}件，适用于批次{batch}。', {**values, 'batch': '、'.join(job_batches)})
            template = CheckTemplate.objects.create(workspace=workspace,name=title,items=[{'id':f'check-{n}','label':label,'required':True,'allow_na':False} for n,label in enumerate(['外观完整性与毛刺','定位孔与装配面','批次标识与交接确认'])])
            ProductionJob.objects.filter(pk__in=jobs).update(template=template)
            AuditEvent.objects.create(workspace=workspace,action='template.published',object_id=str(template.pk),details={'data_origin':'scheduled_demo','schedule_key':key})
        else:
            kind = 'notice'
            heading, text = NOTICES[(i+slot+day.toordinal())%len(NOTICES)]
            title = f'{heading} · {values["line"]}号工位'
            body = render(text, values)
        WorkspaceBulletin.objects.create(workspace=workspace,source_key=f'{key}/{i}',kind=kind,title=title,body=body,published_at=at,job=job,template=template)
        made += 1
    return made
