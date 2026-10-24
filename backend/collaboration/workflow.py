"""Transactional lifecycle commands with immutable receipts and optimistic versions."""
import hashlib
import json
from django.db import transaction
from django.db.models import F, Q
from django.http import Http404
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from .api import membership, job_json
from .models import AuditEvent, CheckTemplate, Evidence, ExceptionCase, JobMutation, Membership, ProductionJob, QualityInspection


class AbortMutation(Exception):
    def __init__(self, response):
        self.response = response


def reject(message, code='invalid_transition'):
    return Response({'detail': message, 'code': code}, status=409)


def event(request, job, action, object_id, **details):
    AuditEvent.objects.create(workspace=job.workspace, user=request.user, job=job,
        version=job.version, action=action, object_id=str(object_id), details=details)


def mutate(request, member, job_id, command):
    try:
        job = ProductionJob.objects.get(pk=job_id, workspace=member.workspace)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    key = request.headers.get('Idempotency-Key', '')
    expected = request.data.get('version')
    cloud = isinstance(request.auth, dict) and bool(request.auth.get('iss'))
    if (key and not 16 <= len(key) <= 64) or (cloud and not key):
        return Response({'detail': '请求标识无效，请重试', 'code': 'idempotency_required'}, status=400)
    if (expected is not None and (type(expected) is not int or expected < 1)) or (cloud and expected is None):
        return Response({'detail': '请刷新任务后重试', 'code': 'version_required'}, status=400)
    fingerprint = hashlib.sha256(json.dumps({'actor': request.user.pk, 'path': request.path,
        'body': request.data}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()

    def receipt():
        prior = JobMutation.objects.filter(job=job, key=key).first() if key else None
        if prior:
            return Response(prior.result, status=prior.status_code) if prior.request_hash == fingerprint else reject('请求标识已用于其他内容', 'idempotency_conflict')
        return None

    previous = receipt()
    if previous is not None:
        return previous
    if expected is not None and expected != job.version:
        return Response({'detail': '任务已更新，请刷新后重试', 'code': 'version_conflict', 'current': job_json(job)}, status=409)
    try:
        with transaction.atomic():
            # First DB statement in this transaction is a conditional write, also
            # serializing writers on SQLite where SELECT FOR UPDATE is a no-op.
            changed = ProductionJob.objects.filter(pk=job.pk, version=job.version).update(version=F('version') + 1)
            if not changed:
                raise AbortMutation(None)
            job.refresh_from_db()
            result = command(job)
            if result.status_code >= 400:
                raise AbortMutation(result)
            if key:
                JobMutation.objects.create(job=job, key=key, request_hash=fingerprint,
                    result=result.data, status_code=result.status_code)
            return result
    except AbortMutation as aborted:
        if aborted.response is not None:
            return aborted.response
        previous = receipt()
        if previous is not None:
            return previous
        job.refresh_from_db()
        return Response({'detail': '任务已更新，请刷新后重试', 'code': 'version_conflict', 'current': job_json(job)}, status=409)


@api_view(['GET', 'PATCH'])
@permission_classes([IsAuthenticated])
def task(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=request.method == 'PATCH')
    if request.method == 'GET':
        try:
            return Response(job_json(ProductionJob.objects.get(pk=job_id, workspace=member.workspace)))
        except ProductionJob.DoesNotExist as exc:
            raise Http404 from exc
    def command(job):
        target = request.data.get('status')
        if target not in {'queued': {'printing'}, 'printing': {'inspection'}}.get(job.status, set()):
            return reject('任务状态无法这样变更')
        old = job.status
        job.status = target
        job.save(update_fields=['status', 'updated_at'])
        event(request, job, 'job.status', job.pk, previous=old, status=target)
        return Response(job_json(job))
    return mutate(request, member, job_id, command)


def inspection_command(request, job, *, exception_only=False):
    if job.status != 'inspection':
        return reject('任务当前不能登记质检结果')
    if job.exceptions.filter(status='open').exists():
        return reject('请先处理所有未完成异常')
    verdict = 'fail' if exception_only else request.data.get('verdict')
    if verdict not in ('pass', 'fail'):
        return Response({'detail': '请选择合格或异常'}, status=400)
    note = str(request.data.get('note', '')).strip()
    if verdict == 'fail' and not note:
        return Response({'detail': '请描述需要复核的问题'}, status=400)
    if len(note) > 500:
        return Response({'detail': '备注不能超过500个字符'}, status=400)
    values = request.data
    inspected = values.get('inspected_qty', job.quantity)
    passed = values.get('pass_qty', job.quantity if verdict == 'pass' else 0)
    failed = values.get('fail_qty', job.quantity if verdict == 'fail' else 0)
    scrapped = values.get('scrap_qty', 0)
    if any(type(value) is not int or value < 0 for value in (inspected, passed, failed, scrapped)) or not 1 <= inspected <= job.quantity or passed + failed + scrapped != inspected:
        return Response({'detail': '送检数量必须等于合格、异常与报废数量之和，且不超过计划数量'}, status=400)
    if (verdict == 'pass' and (failed or scrapped or inspected != job.quantity)) or (verdict == 'fail' and failed + scrapped == 0):
        return Response({'detail': '检验结论与工件数量不一致'}, status=400)
    template_id = job.template_id or values.get('template_id')
    template = CheckTemplate.objects.filter(Q(workspace=job.workspace) | Q(workspace__isnull=True), pk=template_id).first() if template_id else None
    if template_id and template is None:
        return Response({'detail': '检查模板不存在'}, status=400)
    answers, snapshot = values.get('answers', []), {}
    if template:
        if not isinstance(answers, list) or any(not isinstance(answer, dict) for answer in answers):
            return Response({'detail': '检查项格式无效'}, status=400)
        if any(not isinstance(answer.get('id'), str) for answer in answers):
            return Response({'detail': '检查项编号无效'}, status=400)
        by_id = {answer.get('id'): answer for answer in answers}
        known = {item['id'] for item in template.items}
        if len(by_id) != len(answers) or not set(by_id).issubset(known):
            return Response({'detail': '检查项编号重复或不属于模板'}, status=400)
        for item in template.items:
            answer = by_id.get(item['id'], {})
            result = answer.get('result')
            if result is None and not item['required']:
                continue
            if result not in ('pass', 'fail', 'na') or (result == 'na' and not item['allow_na']):
                return Response({'detail': '请完成所有必填检查项'}, status=400)
            if result == 'fail' and (not str(answer.get('note', '')).strip() or verdict != 'fail'):
                return Response({'detail': '不合格项需要问题说明，并选择异常结论'}, status=400)
        snapshot = {'id': template.pk, 'name': template.name, 'version': template.version, 'items': template.items}
    serial_results = values.get('serial_results', {})
    if job.tracking_mode == 'serial':
        if not isinstance(serial_results, dict) or set(serial_results) != set(job.serial_numbers) or any(value not in ('pass', 'fail', 'scrap') for value in serial_results.values()):
            return Response({'detail': '请为任务内每个SN填写唯一检验结论'}, status=400)
        counts = [list(serial_results.values()).count(result) for result in ('pass', 'fail', 'scrap')]
        if counts != [passed, failed, scrapped]:
            return Response({'detail': 'SN结果与工件数量不一致'}, status=400)
    elif serial_results:
        return Response({'detail': '批次检验不可混入SN记录'}, status=400)
    photo_ids = values.get('evidence_ids', [])
    if not isinstance(photo_ids, list) or any(type(value) is not int for value in photo_ids) or len(photo_ids) != len(set(photo_ids)):
        return Response({'detail': '证据编号无效'}, status=400)
    photos = Evidence.objects.filter(job=job, pk__in=photo_ids, inspection__isnull=True, stage='inspection')
    if photos.count() != len(photo_ids):
        return Response({'detail': '图片不属于当前检验或已绑定其他轮次'}, status=400)
    category, severity = values.get('category', 'other'), values.get('severity', 'major')
    if category not in ('surface', 'dimension', 'crack', 'deformation', 'assembly', 'other') or severity not in ('minor', 'major', 'critical'):
        return Response({'detail': '异常类别或严重度无效'}, status=400)
    check = QualityInspection.objects.create(job=job, inspector=request.user, verdict=verdict, note=note,
        round_no=job.quality_inspections.count() + 1, inspected_qty=inspected, pass_qty=passed,
        fail_qty=failed, scrap_qty=scrapped, answers=answers, template_snapshot=snapshot, serial_results=serial_results)
    photos.update(inspection=check)
    if verdict == 'fail':
        from .product import person
        case = ExceptionCase.objects.create(job=job, note=note, assignee=str(request.data.get('assignee') or person(job.assignee) or person(request.user))[:100],
            inspection=check, category=category, severity=severity, creator=request.user)
        event(request, job, 'exception.created', case.pk, inspection_id=check.pk, category=category, severity=severity, assignee=case.assignee)
    job.status = 'closed' if verdict == 'pass' else 'exception'
    job.save(update_fields=['status', 'updated_at'])
    event(request, job, 'inspection.' + verdict, check.pk, verdict=verdict, previous='inspection', status=job.status, round_no=check.round_no, inspected_qty=inspected, pass_qty=passed, fail_qty=failed, scrap_qty=scrapped, evidence_ids=photo_ids)
    if exception_only:
        return Response({'id': case.pk, 'status': case.status, 'note': case.note, 'assignee': case.assignee,
                         'job_version': job.version}, status=201)
    return Response(job_json(job), status=201)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def inspect(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    return mutate(request, member, job_id, lambda job: inspection_command(request, job))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def assign(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    def command(job):
        from .product import person
        if job.status == 'closed':
            return reject('已关闭任务不能更改负责人')
        if 'assignee_id' not in request.data:
            return Response({'detail': '请选择负责人或未指派'}, status=400)
        selected = request.data['assignee_id']
        if selected is not None and (type(selected) is not int or not 1 <= selected <= 2**63-1):
            return Response({'detail': '负责人编号无效'}, status=400)
        target = Membership.objects.select_related('user', 'user__cloud_identity').filter(
            workspace=member.workspace, user_id=selected, user__is_active=True,
            role__in=[Membership.OWNER, Membership.OPERATOR]).first() if selected is not None else None
        if selected is not None and target is None:
            return Response({'detail': '请选择当前团队可处理任务的成员'}, status=400)
        if selected == job.assignee_id:
            return Response({'detail': '负责人未改变'}, status=400)
        note = str(request.data.get('note', '')).strip()
        if len(note) > 500 or (job.status == 'exception' and not note):
            return Response({'detail': '异常交接需要填写1至500字的交接说明'}, status=400)
        previous_id, previous = job.assignee_id, person(job.assignee)
        current = person(target.user) if target else ''
        # Pending issues follow the task's responsible member. Resolved issues
        # and their inspection/resolution history remain unchanged.
        pending = list(job.exceptions.filter(status='open').values('id', 'assignee'))
        job.exceptions.filter(status='open').update(assignee=current)
        job.assignee_id = selected
        job.save(update_fields=['assignee', 'updated_at'])
        event(request, job, 'job.assigned', job.pk, previous_assignee_id=previous_id,
            previous_assignee=previous, assignee_id=selected, assignee=current,
            note=note, handed_over_issues=pending, actor_role=member.role)
        return Response(job_json(job))
    return mutate(request, member, job_id, command)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def exception(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    return mutate(request, member, job_id, lambda job: inspection_command(request, job, exception_only=True))


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def resolve(request, workspace_id, case_id):
    member = membership(request, workspace_id, write=True)
    try:
        case = ExceptionCase.objects.get(pk=case_id, job__workspace=member.workspace)
    except ExceptionCase.DoesNotExist as exc:
        raise Http404 from exc
    def command(job):
        case.refresh_from_db()
        if job.status != 'exception' or case.status != 'open':
            return reject('异常已处理或任务状态已更新，请刷新后重试')
        resolution = str(request.data.get('resolution', '')).strip()
        if not resolution or len(resolution) > 500:
            return Response({'detail': '请填写1至500字的处理结果'}, status=400)
        target = request.data.get('next_status', 'inspection')
        if target not in ('inspection', 'closed'):
            return Response({'detail': '处理后任务状态无效'}, status=400)
        disposition = request.data.get('disposition')
        reason = str(request.data.get('closure_reason', '')).strip()
        other_open = job.exceptions.filter(status='open').exclude(pk=case.pk).exists()
        if target == 'closed':
            if member.role != Membership.OWNER:
                raise PermissionDenied('仅团队管理员可授权关闭')
            if disposition not in ('scrapped', 'concession') or not reason or len(reason) > 500:
                return Response({'detail': '请选择关闭处置并填写授权依据'}, status=400)
            if other_open:
                return reject('请先处理所有未完成异常')
        previous = job.status
        case.status, case.resolution, case.resolved_at = 'resolved', resolution, timezone.now()
        case.save(update_fields=['status', 'resolution', 'resolved_at'])
        job.status = 'exception' if other_open else target
        job.save(update_fields=['status', 'updated_at'])
        event(request, job, 'exception.resolved', case.pk, resolution=resolution,
            previous=previous, status=job.status, disposition=disposition if target == 'closed' else None,
            closure_reason=reason if target == 'closed' else None, actor_role=member.role)
        return Response({'status': case.status, 'job_status': job.status, 'job_version': job.version})
    return mutate(request, member, case.job_id, command)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def history(request, workspace_id, job_id):
    member = membership(request, workspace_id)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    rows = AuditEvent.objects.filter(workspace=member.workspace).filter(Q(job=job) |
        Q(job__isnull=True, object_id=str(job.pk), action__startswith='job.')).select_related('user', 'user__cloud_identity').order_by('created_at', 'pk')
    checks = {str(check.pk): check for check in job.quality_inspections.all()}
    output = []
    for row in rows:
        kind = 'inspection' if row.action.startswith('inspection.') else 'issue' if row.action.startswith('exception.') else 'evidence' if row.action.startswith('evidence.') else 'task'
        record = None
        if kind == 'inspection' and (check := checks.get(row.object_id)):
            record = {'id':check.pk, 'round_no':check.round_no, 'verdict':check.verdict,
                'inspected_qty':check.inspected_qty, 'pass_qty':check.pass_qty, 'fail_qty':check.fail_qty,
                'scrap_qty':check.scrap_qty, 'template_version':check.template_snapshot.get('version')}
        identity = getattr(row.user, 'cloud_identity', None)
        output.append({'id':row.pk, 'job_id':str(job.pk), 'workspace_id':member.workspace_id,
            'action':row.action, 'object_id':row.object_id, 'object_type':kind,
            'version':row.version, 'details':row.details, 'record':record,
            'created_at':row.created_at.isoformat(), 'actor_id':row.user_id,
            'actor':(identity.display_name if identity else row.user.get_full_name() or row.user.username) if row.user else ''})
    return Response(output)
