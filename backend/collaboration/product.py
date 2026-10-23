"""Workspace-scoped templates, records, piece metrics and report projections."""
import csv
import io
from datetime import timedelta
from django.db import transaction
from django.db.models import Q, F
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response
from .api import membership
from .models import AuditEvent, CheckTemplate, Membership, QualityInspection, Workspace, NotificationReceipt


def person(user):
    if user is None:
        return ''
    identity = getattr(user, 'cloud_identity', None)
    return identity.display_name if identity else user.get_full_name() or user.username


def template_json(item):
    return {'id': item.pk, 'name': item.name, 'version': item.version, 'items': item.items, 'built_in': item.workspace_id is None}


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def templates(request, workspace_id):
    member = membership(request, workspace_id, write=request.method == 'POST')
    if request.method == 'GET':
        rows = CheckTemplate.objects.filter(Q(workspace=member.workspace) | Q(workspace__isnull=True)).order_by('name', '-version')
        return Response([template_json(item) for item in rows])
    if member.role != Membership.OWNER:
        raise PermissionDenied('仅团队管理员可发布模板')
    name, items = str(request.data.get('name', '')).strip(), request.data.get('items')
    if not name or len(name) > 100 or not isinstance(items, list) or not 3 <= len(items) <= 6:
        raise ValidationError('请填写模板名称和3至6个检查项')
    ids = set()
    normalized = []
    for item in items:
        if not isinstance(item, dict):
            raise ValidationError('检查项格式无效')
        item_id, label = str(item.get('id', '')), str(item.get('label', '')).strip()
        if not item_id or len(item_id) > 64 or item_id in ids or not label or len(label) > 120:
            raise ValidationError('检查项编号或名称无效')
        ids.add(item_id)
        normalized.append({'id': item_id, 'label': label, 'required': item.get('required') is True, 'allow_na': item.get('allow_na') is True})
    with transaction.atomic():
        Workspace.objects.filter(pk=workspace_id).update(name=F('name'))
        previous = CheckTemplate.objects.filter(workspace=member.workspace, name=name).order_by('-version').first()
        item = CheckTemplate.objects.create(workspace=member.workspace, name=name, version=previous.version + 1 if previous else 1, items=normalized)
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, action='template.published', object_id=str(item.pk), version=item.version)
    return Response(template_json(item), status=201)


def inspection_json(check):
    return {'id': check.pk, 'task_id': str(check.job_id), 'part_name': check.job.part_name, 'batch_code': check.job.batch_code,
        'round_no': check.round_no, 'verdict': check.verdict, 'note': check.note, 'inspector': person(check.inspector),
        'created_at': check.created_at.isoformat(), 'inspected_qty': check.inspected_qty, 'pass_qty': check.pass_qty,
        'fail_qty': check.fail_qty, 'scrap_qty': check.scrap_qty, 'template_snapshot': check.template_snapshot,
        'answers': check.answers, 'serial_results': check.serial_results,
        'evidence': [{'id': photo.pk, 'stage': photo.stage, 'issue_id': photo.issue_id} for photo in check.photos.all()]}


def filtered_jobs(request, member):
    rows = member.workspace.jobs.all().order_by('-created_at')
    query = str(request.query_params.get('q', '')).strip()
    if query:
        rows = rows.filter(Q(part_name__icontains=query) | Q(batch_code__icontains=query) | Q(id__icontains=query) | Q(printer__icontains=query))
    if request.query_params.get('status'):
        rows = rows.filter(status=request.query_params['status'])
    if request.query_params.get('mine') == 'true':
        rows = rows.filter(assignee=request.user)
    for key, field in [('from', 'created_at__gte'), ('to', 'created_at__lt')]:
        if request.query_params.get(key):
            from django.utils.dateparse import parse_datetime
            instant = parse_datetime(request.query_params[key])
            if instant is None or timezone.is_naive(instant):
                raise ValidationError('日期筛选需要包含时区')
            rows = rows.filter(**{field: instant})
    return rows


def projection(request, member):
    jobs = list(filtered_jobs(request, member).prefetch_related('quality_inspections', 'exceptions'))
    first_total = first_pass = final_total = final_pass = fail = scrap = 0
    trends, categories, durations = {}, {}, []
    for job in jobs:
        checks = list(job.quality_inspections.order_by('round_no', 'created_at', 'pk'))
        first, last = (checks[0], checks[-1]) if checks else (None, None)
        if first and first.inspected_qty is not None:
            first_total += first.inspected_qty; first_pass += first.pass_qty
            day = first.created_at.date().isoformat()
            row = trends.setdefault(day, {'day': day, 'inspected': 0, 'passed': 0})
            row['inspected'] += first.inspected_qty; row['passed'] += first.pass_qty
        if last and last.inspected_qty is not None:
            final_total += job.quantity
            final_pass += last.pass_qty if job.status == 'closed' and last.verdict == 'pass' else 0
            fail += last.fail_qty; scrap += last.scrap_qty
        for issue in job.exceptions.all():
            categories[issue.category] = categories.get(issue.category, 0) + 1
            if issue.resolved_at:
                durations.append((issue.resolved_at - issue.created_at).total_seconds())
    counts = {state: sum(j.status == state for j in jobs) for state in ('queued', 'printing', 'inspection', 'exception', 'closed')}
    today = timezone.now().date()
    trend = [trends.get((today - timedelta(days=i)).isoformat(), {'day': (today - timedelta(days=i)).isoformat(), 'inspected': 0, 'passed': 0}) for i in range(6, -1, -1)]
    return {'task_counts': counts, 'first_inspected_pieces': first_total, 'first_pass_pieces': first_pass,
        'first_pass_rate': first_pass / first_total if first_total else None,
        'final_planned_pieces': final_total, 'final_released_pieces': final_pass,
        'final_release_rate': final_pass / final_total if final_total else None,
        'latest_fail_pieces': fail, 'latest_scrap_pieces': scrap, 'trend': trend, 'issue_categories': categories,
        'average_issue_seconds': sum(durations) / len(durations) if durations else None,
        'unknown_quantity_checks': QualityInspection.objects.filter(job__in=jobs, inspected_qty__isnull=True).count(),
        'task_ids': [str(job.pk) for job in jobs]}


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def records(request, workspace_id):
    member = membership(request, workspace_id)
    rows = QualityInspection.objects.filter(job__in=filtered_jobs(request, member)).select_related('job', 'inspector', 'inspector__cloud_identity').prefetch_related('photos').order_by('-created_at', '-pk')
    if request.query_params.get('verdict'):
        rows = rows.filter(verdict=request.query_params['verdict'])
    return Response([inspection_json(row) for row in rows])


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def metrics(request, workspace_id):
    return Response(projection(request, membership(request, workspace_id)))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def report(request, workspace_id):
    member = membership(request, workspace_id)
    payload = projection(request, member)
    if request.query_params.get('download') == 'csv':
        out = io.StringIO(); writer = csv.writer(out)
        writer.writerow(['metric', 'value'])
        for key in ('first_inspected_pieces', 'first_pass_pieces', 'first_pass_rate', 'final_planned_pieces', 'final_released_pieces', 'final_release_rate', 'latest_fail_pieces', 'latest_scrap_pieces'):
            writer.writerow([key, payload[key]])
        response = HttpResponse('\ufeff' + out.getvalue(), content_type='text/csv; charset=utf-8')
        response['Content-Disposition'] = 'attachment; filename="linesight-quality.csv"'
        return response
    from .api import job_json
    return Response({'workspace': member.workspace.name, 'generated_at': timezone.now().isoformat(),
                     'jobs': [job_json(job) for job in filtered_jobs(request, member)] if request.query_params.get('q') else [],
                     'metrics': payload, 'tasks': [job.pk for job in filtered_jobs(request, member)]})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def notifications(request, workspace_id):
    member = membership(request, workspace_id)
    rows = member.workspace.jobs.filter(Q(assignee=request.user) | Q(assignee__isnull=True)).filter(status__in=['inspection', 'exception']).order_by('-updated_at')
    seen = dict(NotificationReceipt.objects.filter(user=request.user, job__workspace=member.workspace).values_list('job_id', 'version'))
    return Response([{'id': str(job.pk), 'task_id': str(job.pk), 'version': job.version, 'read': seen.get(job.pk, 0) >= job.version, 'part_name': job.part_name,
        'status': job.status, 'updated_at': job.updated_at.isoformat(),
        'reinspection': job.status == 'inspection' and job.quality_inspections.exists()} for job in rows])


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def read_notification(request, workspace_id, job_id):
    from django.http import Http404
    member = membership(request, workspace_id)
    with transaction.atomic():
        Workspace.objects.filter(pk=workspace_id).update(name=F('name'))
        job = member.workspace.jobs.filter(pk=job_id).filter(Q(assignee=request.user) | Q(assignee__isnull=True)).first()
        if job is None:
            raise Http404
        version = request.data.get('version')
        if type(version) is not int or not 1 <= version <= job.version:
            raise ValidationError('请刷新通知后重试')
        receipt = NotificationReceipt.objects.filter(user=request.user, job=job).first()
        if receipt is None:
            receipt = NotificationReceipt.objects.create(user=request.user, job=job, version=version)
        elif version > receipt.version:
            receipt.version = version
            receipt.save(update_fields=['version', 'read_at'])
    return Response({'task_id': str(job.pk), 'read': receipt.version >= job.version, 'version': receipt.version})
