import io
import json
import hashlib
import re
import mimetypes
import secrets
import time
from datetime import timedelta
from PIL import Image, UnidentifiedImageError
import cv2
import numpy as np
from django.contrib.auth import authenticate, get_user_model
from django.conf import settings
from django.core import signing
from django.core.validators import URLValidator
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.files.base import ContentFile
from django.db import transaction
from django.db.models import F, Q
from django.http import Http404
from django.http import FileResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import JSONParser, MultiPartParser, FormParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied, AuthenticationFailed
from .models import AuditEvent, CheckTemplate, ExceptionCase, Evidence, Invitation, InvitationRedemption, JobProfileMetadata, JobRequest, LegacyInspection, Membership, PieceSerial, PrinterProfile, ProductionJob, QualityInspection, Workspace
from .avatars import portrait


def membership(request, workspace_id, write=False):
    try:
        member = Membership.objects.select_related("workspace").get(workspace_id=workspace_id, user=request.user)
    except Membership.DoesNotExist as exc:
        raise Http404 from exc
    if isinstance(request.auth, dict):
        if request.auth.get("is_demo") and member.workspace.kind != "demo":
            raise Http404
        if member.token_not_before and request.auth.get("iat", 0) <= member.token_not_before.timestamp():
            raise AuthenticationFailed("成员权限已更新，请重新登录")
    if write and member.role == Membership.VIEWER:
        raise PermissionDenied("当前成员仅可查看")
    return member


@api_view(["POST"])
@permission_classes([AllowAny])
def register(request):
    # Public registration stays retired even if identity configuration is missing.
    # Accounts are provisioned administratively through the identity provider.
    return Response({"detail": "请使用统一登录入口"}, status=410)


@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    if getattr(settings, "LINESIGHT_OIDC_ISSUER", ""):
        return Response({"detail": "请使用统一登录入口"}, status=410)
    user = authenticate(username=request.data.get("username", ""), password=request.data.get("password", ""))
    if user is None:
        return Response({"detail": "用户名或密码错误"}, status=401)
    token = signing.dumps({"uid": user.pk, "iat": time.time()}, salt="linesight-access", compress=True)
    return Response({"access": token, "expires_in": 3600})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def create_workspace(request):
    if isinstance(request.auth, dict) and request.auth.get("is_demo"):
        raise PermissionDenied("演示账号仅使用演示团队")
    name = str(request.data.get("name", "")).strip()
    if not 1 <= len(name) <= 100:
        return Response({"detail": "请填写工作区名称"}, status=400)
    with transaction.atomic():
        ws = Workspace.objects.create(name=name)
        Membership.objects.create(workspace=ws, user=request.user, role=Membership.OWNER)
    return Response({"id": ws.pk, "name": ws.name, "role": "owner"}, status=201)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def workspaces(request):
    rows = Membership.objects.filter(user=request.user).select_related("workspace")
    if isinstance(request.auth, dict) and request.auth.get("is_demo"):
        rows = rows.filter(workspace__kind="demo")
    return Response([{"id": m.workspace_id, "name": m.workspace.name, "role": m.role, "kind": m.workspace.kind} for m in rows])


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def account(request):
    identity = getattr(request.user, "cloud_identity", None)
    if identity is None:
        return Response({"detail": "请使用统一登录入口"}, status=409)
    if request.method == "PATCH":
        if identity.is_demo:
            raise PermissionDenied("演示账号不可修改共享资料")
        name = str(request.data.get("display_name", "")).strip()
        if not 1 <= len(name) <= 100:
            return Response({"detail": "显示名称需要1至100个字符"}, status=400)
        identity.display_name = name
        identity.save(update_fields=["display_name"])
    return Response({"id": str(identity.pk), "username": request.auth.get("preferred_username", ""),
        "display_name": identity.display_name, "is_demo": identity.is_demo,
        "avatar_data": portrait(identity.avatar_seed), "job_title": identity.job_title,
        "home_workspace_id": identity.home_workspace_id, "provider": "keycloak"})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def members(request, workspace_id):
    member = membership(request, workspace_id)
    rows = Membership.objects.filter(workspace=member.workspace).select_related("user", "user__cloud_identity").order_by("user__username")
    return Response([{"id": row.user_id, "username": row.user.username, "role": row.role, "active": row.user.is_active, "is_self": row.user_id == request.user.pk,
        "display_name": identity.display_name if (identity := getattr(row.user, "cloud_identity", None)) else row.user.get_full_name() or row.user.username,
        "avatar_data": portrait(identity.avatar_seed) if identity else '',
        "job_title": identity.job_title if identity else ''} for row in rows])


@api_view(["PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def manage_member(request, workspace_id, username):
    # Serialize administration within a workspace, including simultaneous owners
    # leaving. Membership is read afresh on every API request, never from a token.
    with transaction.atomic():
        member = membership(request, workspace_id)
        Workspace.objects.select_for_update().get(pk=workspace_id)
        member = membership(request, workspace_id)
        if member.role != Membership.OWNER:
            raise PermissionDenied("仅团队管理员可管理成员")
        try:
            target = Membership.objects.select_related("user").get(
                workspace_id=workspace_id, user__username=username)
        except Membership.DoesNotExist as exc:
            raise Http404 from exc
        if target.user_id == request.user.pk:
            return Response({"detail": "请使用离开团队操作；不可直接修改自己的权限"}, status=409)
        role = request.data.get("role")
        if request.method == "PATCH" and role not in dict(Membership.ROLES):
            return Response({"detail": "成员角色无效"}, status=400)
        if target.role == Membership.OWNER and (request.method == "DELETE" or role != Membership.OWNER):
            if not Membership.objects.filter(workspace_id=workspace_id, role=Membership.OWNER).exclude(pk=target.pk).exists():
                return Response({"detail": "团队必须保留至少一位管理员"}, status=409)
        before = target.role
        if request.method == "DELETE":
            target.delete()
            action = "member.removed"
        else:
            target.role = role
            target.token_not_before = timezone.now()
            target.save(update_fields=["role", "token_not_before"])
            action = "member.role"
        AuditEvent.objects.create(workspace=member.workspace, user=request.user,
            action=action, object_id=str(target.user_id))
    return Response({"username": username, "previous_role": before,
                     "role": role if request.method == "PATCH" else None})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def leave_workspace(request, workspace_id):
    if isinstance(request.auth, dict) and request.auth.get("is_demo"):
        raise PermissionDenied("演示账号仅使用演示团队")
    with transaction.atomic():
        member = membership(request, workspace_id)
        Workspace.objects.select_for_update().get(pk=workspace_id)
        member = membership(request, workspace_id)
        if member.role == Membership.OWNER and not Membership.objects.filter(
                workspace_id=workspace_id, role=Membership.OWNER).exclude(pk=member.pk).exists():
            return Response({"detail": "请先将另一位成员设为管理员，再离开团队"}, status=409)
        AuditEvent.objects.create(workspace=member.workspace, user=request.user,
            action="member.left", object_id=str(request.user.pk))
        member.delete()
    return Response(status=204)


STARTER_PROFILES = [
    {"id": "starter:a1", "name": "Bambu Lab A1", "version": "starter-v1", "source": "https://bambulab.com/en/a1", "note": "Printer profile reference"},
    {"id": "starter:p2s", "name": "Bambu Lab P2S", "version": "starter-v1", "source": "https://bambulab.com/en/p2s", "note": "Printer profile reference"},
]


def profile_json(profile):
    from .product import template_json
    return {"id": f"workspace:{profile.pk}", "name": profile.name, "version": profile.version,
        "source": profile.source_url, "note": profile.note, "override": True,
        "revision": profile.revision, "default_template_id": profile.default_template_id,
        "default_template": template_json(profile.default_template) if profile.default_template_id else None}


def resolve_profile(workspace, key):
    if key.startswith("starter:"):
        return next(({**item, "revision": 0, "default_template_id": None, "default_template": None}
            for item in STARTER_PROFILES if item["id"] == key), None)
    if key.startswith("workspace:"):
        try:
            item = PrinterProfile.objects.select_related('default_template').get(pk=int(key.split(":", 1)[1]), workspace=workspace)
            return profile_json(item)
        except (ValueError, OverflowError, PrinterProfile.DoesNotExist):
            pass
    return None


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def printer_profiles(request, workspace_id):
    member = membership(request, workspace_id, write=request.method == "POST")
    if request.method == "GET":
        overrides = PrinterProfile.objects.filter(workspace=member.workspace).select_related('default_template').order_by("name")
        return Response([{**p, "revision": 0, "default_template_id": None, "default_template": None} for p in STARTER_PROFILES]
            + [profile_json(p) for p in overrides])
    if member.role not in (Membership.OWNER, Membership.MANAGER):
        raise PermissionDenied("仅工作区所有者可维护打印机配置")
    d = request.data
    key = request.headers.get('Idempotency-Key', '')
    cloud = isinstance(request.auth, dict) and bool(request.auth.get('iss'))
    if (key and not 16 <= len(key) <= 64) or (cloud and not key):
        return Response({'detail': '请求标识无效，请重试', 'code': 'idempotency_required'}, status=400)
    name, version = str(d.get("name", "")).strip(), str(d.get("version", "")).strip()
    source, note = str(d.get("source", "")).strip(), str(d.get("note", "")).strip()
    valid_source = len(source) <= 300
    try:
        URLValidator(schemes=['https'])(source)
    except DjangoValidationError:
        valid_source = False
    if not name or len(name) > 80 or not version or len(version) > 40 or not valid_source or len(note) > 300:
        return Response({"detail": "请填写配置名称、版本和有效 HTTPS 来源"}, status=400)
    template_id = d.get('default_template_id')
    template = None
    if template_id is not None:
        if type(template_id) is not int:
            return Response({'detail': '检查模板不存在'}, status=400)
        template = CheckTemplate.objects.filter(Q(workspace=member.workspace) | Q(workspace__isnull=True), pk=template_id).first()
        if template is None:
            return Response({'detail': '检查模板不存在'}, status=400)
    fingerprint = hashlib.sha256(json.dumps({'actor': request.user.pk, 'body': d}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    with transaction.atomic():
        Workspace.objects.filter(pk=workspace_id).update(name=F('name'))
        prior = AuditEvent.objects.filter(workspace=member.workspace, action='profile.saved', details__request_key=key).first() if key else None
        if prior:
            if prior.user_id != request.user.pk or prior.details.get('request_hash') != fingerprint:
                return Response({'detail': '请求标识已用于其他内容', 'code': 'idempotency_conflict'}, status=409)
            return Response(prior.details['result'], status=prior.details['response_status'])
        profile_id = d.get('id')
        item = None
        if profile_id is not None:
            resolved = resolve_profile(member.workspace, str(profile_id))
            if not resolved or not resolved.get('override'):
                return Response({'detail': '团队打印配置不存在'}, status=404)
            item = PrinterProfile.objects.get(pk=int(str(profile_id).split(':')[1]), workspace=member.workspace)
            if name != item.name:
                return Response({'detail': '修改配置名称请使用复制功能'}, status=400)
            if type(d.get('revision')) is not int or d['revision'] != item.revision:
                return Response({'detail': '配置已更新，请核对最新版本', 'code': 'profile_version_conflict', 'current': profile_json(item)}, status=409)
        else:
            item = PrinterProfile.objects.filter(workspace=member.workspace, name=name).first()
            if item and cloud:
                return Response({'detail': '同名配置已存在，请编辑现有配置或使用其他名称', 'code': 'profile_name_conflict', 'current': profile_json(item)}, status=409)
        created = item is None
        if created:
            item = PrinterProfile(workspace=member.workspace, name=name)
        else:
            item.revision += 1
        item.version, item.source_url, item.note = version, source, note
        # Legacy updates that predate template binding leave that binding intact.
        if 'default_template_id' in d or created:
            item.default_template = template
        item.save()
        result = profile_json(item)
        response_status = 201 if created else 200
        details = {'request_key': key, 'request_hash': fingerprint, 'result': result, 'response_status': response_status}
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, action='profile.saved', object_id=str(item.pk), version=item.revision, details=details)
    return Response(result, status=response_status)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def legacy_inspections(request, workspace_id):
    member = membership(request, workspace_id, write=request.method == "POST")
    if request.method == "GET":
        rows = member.workspace.legacy_inspections
        recent = rows.order_by("-created_at")[:100]
        return Response({"count": rows.count(), "sample_count": rows.filter(payload__sample=True).count(),
            "records": [{"id": row.source_id, "at": row.payload.get("at", ""),
                         "recipe": row.payload.get("recipeName", ""), "serial": row.payload.get("serial", ""),
                         "passed": (row.payload.get("review") == "pass" if row.payload.get("review") in ("pass", "fail") else row.payload.get("passed") is True),
                         "original_passed": row.payload.get("passed") is True,
                         "review": row.payload.get("review"), "sample": row.payload.get("sample", False)}
                        for row in recent]})
    if int(request.META.get("CONTENT_LENGTH", 0)) > 5 * 1024 * 1024:
        return Response({"detail": "导入内容超过 5 MB，请分批导入"}, status=413)
    records = request.data.get("records")
    include_samples = request.data.get("include_samples") is True
    if not isinstance(records, list) or len(records) > 5000:
        return Response({"detail": "导入记录数量无效或超过 5000 条"}, status=400)
    validated = []
    for item in records:
        if not isinstance(item, dict):
            return Response({"detail": "记录格式无效"}, status=400)
        source_id = str(item.get("id", ""))
        timestamp = str(item.get("at", ""))
        if not source_id or len(source_id) > 64 or not timestamp or len(timestamp) > 64:
            return Response({"detail": "记录编号或时间无效"}, status=400)
        validated.append((item, source_id, item.get("sample", False) is True))
    imported = skipped = 0
    with transaction.atomic():
        for item, source_id, sample in validated:
            if sample and not include_samples:
                skipped += 1
                continue
            row, created = LegacyInspection.objects.get_or_create(
                workspace=member.workspace, source_id=source_id, defaults={"payload": item}
            )
            imported += int(created)
            skipped += int(not created)
    AuditEvent.objects.create(workspace=member.workspace, user=request.user,
                              action="legacy.import", object_id=f"{imported}:{skipped}")
    return Response({"imported": imported, "skipped": skipped}, status=201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def invite(request, workspace_id):
    member = membership(request, workspace_id, write=True)
    if member.role != Membership.OWNER:
        raise PermissionDenied("仅工作区所有者可邀请成员")
    role = request.data.get("role", Membership.OPERATOR)
    if role not in (Membership.MANAGER, Membership.OPERATOR, Membership.VIEWER):
        return Response({"detail": "邀请角色无效"}, status=400)
    token = secrets.token_urlsafe(24)
    Invitation.objects.create(workspace=member.workspace, token_hash=Invitation.digest(token), role=role,
                              expires_at=timezone.now() + timedelta(hours=48))
    return Response({"code": token, "role": role, "expires_in": 172800}, status=201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def redeem(request):
    if isinstance(request.auth, dict) and request.auth.get("is_demo"):
        raise PermissionDenied("演示账号仅使用演示团队")
    token = request.data.get("code", "")
    if not isinstance(token, str) or not 16 <= len(token) <= 128:
        return Response({"detail": "邀请无效或已使用"}, status=400)
    with transaction.atomic():
        try:
            inv = Invitation.objects.select_for_update().get(token_hash=Invitation.digest(token), redeemed_at__isnull=True)
        except Invitation.DoesNotExist:
            prior = InvitationRedemption.objects.select_related("invitation__workspace").filter(
                invitation__token_hash=Invitation.digest(token), user=request.user
            ).first()
            if prior and Membership.objects.filter(workspace=prior.invitation.workspace, user=request.user).exists():
                return Response({"id": prior.invitation.workspace_id, "name": prior.invitation.workspace.name,
                                 "role": prior.invitation.role, "reused": True}, status=200)
            return Response({"detail": "邀请无效或已使用"}, status=404)
        if inv.expires_at <= timezone.now():
            return Response({"detail": "邀请已过期"}, status=410)
        if Membership.objects.filter(workspace=inv.workspace, user=request.user).exists():
            return Response({"detail": "你已加入此工作区"}, status=409)
        Membership.objects.create(workspace=inv.workspace, user=request.user, role=inv.role)
        InvitationRedemption.objects.create(invitation=inv, user=request.user)
        inv.redeemed_at = timezone.now()
        inv.save(update_fields=["redeemed_at"])
    return Response({"id": inv.workspace_id, "name": inv.workspace.name, "role": inv.role}, status=201)


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def jobs(request, workspace_id):
    member = membership(request, workspace_id, write=request.method == "POST")
    if request.method == "GET":
        from .product import filtered_jobs
        return Response([job_json(x) for x in filtered_jobs(request, member)])
    d = request.data
    part, printer, quantity = str(d.get("part_name", "")).strip(), str(d.get("printer", "")).strip(), d.get("quantity")
    if not part or len(part) > 100 or not printer or len(printer) > 80 or type(quantity) is not int or not 1 <= quantity <= 999:
        return Response({"detail": "任务名称、设备和数量不符合要求"}, status=400)
    profile_id = str(d.get("profile_id", ""))
    profile = resolve_profile(member.workspace, profile_id) if profile_id else None
    if profile_id and profile is None:
        return Response({"detail": "打印机配置不存在或不属于此工作区"}, status=404)
    if profile:
        printer = profile["name"]
    request_id = request.headers.get("Idempotency-Key", "")
    batch = str(d.get('batch_code', '')).strip()
    mode, serials = d.get('tracking_mode', 'batch'), d.get('serial_numbers', [])
    if len(batch) > 80 or mode not in ('batch', 'serial') or not isinstance(serials, list):
        return Response({'detail': '批次或追溯模式无效'}, status=400)
    if mode == 'serial':
        if len(serials) != quantity or any(not isinstance(s, str) or not s.strip() or len(s) > 100 for s in serials) or len(set(serials)) != len(serials):
            return Response({'detail': 'SN需要与工件数量一致且不能重复'}, status=400)
    elif serials:
        return Response({'detail': '批次模式不可混入SN记录'}, status=400)
    assignee_id = d.get('assignee_id')
    if assignee_id is not None and (type(assignee_id) is not int or not 1 <= assignee_id <= 2**63-1 or not Membership.objects.filter(
            workspace=member.workspace, user_id=assignee_id, user__is_active=True,
            role__in=[Membership.OWNER, Membership.MANAGER, Membership.OPERATOR]).exists()):
        return Response({'detail': '负责人不属于当前团队'}, status=400)
    template = None
    if d.get('template_id') is not None:
        template = CheckTemplate.objects.filter(Q(workspace=member.workspace) | Q(workspace__isnull=True), pk=d['template_id']).first()
        if template is None:
            return Response({'detail': '检查模板不存在'}, status=400)
    note = str(d.get("note", ""))[:500]
    payload = json.dumps({"part_name": part, "printer": printer, "quantity": quantity, "note": note,
                          "profile_id": profile_id, 'batch_code': batch, 'tracking_mode': mode,
                          'serial_numbers': serials, 'assignee_id': assignee_id, 'template_id': template.pk if template else None}, sort_keys=True, ensure_ascii=False)
    if 'profile_revision' in d:
        payload = json.dumps({'payload': json.loads(payload), 'profile_revision': d['profile_revision']}, sort_keys=True, ensure_ascii=False)
    payload_hash = hashlib.sha256(payload.encode()).hexdigest()
    if request_id:
        if not 16 <= len(request_id) <= 64:
            return Response({"detail": "任务请求标识无效"}, status=400)
        prior = JobRequest.objects.filter(workspace=member.workspace, request_id=request_id).select_related("job").first()
        if prior:
            if prior.request_hash != payload_hash:
                return Response({"detail": "任务请求标识已用于其他内容"}, status=409)
            return Response(job_json(prior.job), status=200)
    with transaction.atomic():
        Workspace.objects.filter(pk=member.workspace_id).update(name=F("name"))
        if request_id:
            prior = JobRequest.objects.filter(workspace=member.workspace, request_id=request_id).select_related("job").first()
            if prior:
                if prior.request_hash != payload_hash:
                    return Response({"detail": "任务请求标识已用于其他内容"}, status=409)
                return Response(job_json(prior.job), status=200)
        if profile_id:
            profile = resolve_profile(member.workspace, profile_id)
            if profile is None:
                return Response({'detail': '打印机配置不存在或不属于此工作区'}, status=404)
            if 'profile_revision' in d and (type(d['profile_revision']) is not int or d['profile_revision'] != profile['revision']):
                return Response({'detail': '配置已更新，请重新选择打印配置', 'code': 'profile_version_conflict', 'current': profile}, status=409)
            printer = profile['name']
            if 'template_id' not in d and profile.get('default_template_id'):
                template = CheckTemplate.objects.get(pk=profile['default_template_id'])
        if mode == 'serial' and PieceSerial.objects.filter(workspace=member.workspace, serial__in=serials).exists():
            return Response({'detail': 'SN已属于其他任务，不可重复统计'}, status=409)
        job = ProductionJob.objects.create(workspace=member.workspace, part_name=part, printer=printer,
            quantity=quantity, note=note, batch_code=batch, tracking_mode=mode, serial_numbers=serials,
            assignee_id=assignee_id, template=template)
        if mode == 'serial':
            PieceSerial.objects.bulk_create([PieceSerial(workspace=member.workspace, job=job, serial=serial) for serial in serials])
        if profile:
            JobProfileMetadata.objects.create(job=job, version=profile["version"], source_url=profile["source"])
        if request_id:
            JobRequest.objects.create(workspace=member.workspace, request_id=request_id, request_hash=payload_hash, job=job)
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, job=job, version=job.version,
            action="job.created", object_id=str(job.pk), details={"status": "queued"})
    return Response(job_json(job), status=201)


def job_json(job):
    from .product import inspection_json, person, template_json
    profile = getattr(job, "profile_metadata", None)
    return {"id": str(job.pk), "version": job.version, "part_name": job.part_name, "printer": job.printer, "quantity": job.quantity,
            "note": job.note, "status": job.status, "created_at": job.created_at.isoformat(),
            'updated_at': job.updated_at.isoformat(), 'batch_code': job.batch_code, 'tracking_mode': job.tracking_mode,
            'serial_numbers': job.serial_numbers, 'assignee_id': job.assignee_id, 'assignee': person(job.assignee),
            'template': template_json(job.template) if job.template_id else None,
            "profile_version": profile.version if profile else "", "profile_source": profile.source_url if profile else "",
            "exceptions": [{"id": x.pk, "note": x.note, "status": x.status, "assignee": x.assignee,
                            "resolution": x.resolution, 'category': x.category, 'severity': x.severity,
                            'inspection_id': x.inspection_id, 'creator': person(x.creator), 'created_at': x.created_at.isoformat(),
                            'resolved_at': x.resolved_at.isoformat() if x.resolved_at else None} for x in job.exceptions.order_by("-created_at")],
            "inspections": [inspection_json(x) for x in job.quality_inspections.order_by('-round_no', '-created_at')],
            "evidence": [{"id": x.pk, "created_at": x.created_at.isoformat(), 'stage': x.stage,
                          'inspection_id': x.inspection_id, 'issue_id': x.issue_id} for x in job.evidence.order_by("-created_at")]}






@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def upload_evidence(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    stage = request.data.get('stage', 'inspection')
    issue, inspection = None, None
    if stage not in ('inspection', 'before', 'after'):
        return Response({'detail': '证据阶段无效'}, status=400)
    file = request.FILES.get('image')
    if file is None or file.size > 10 * 1024 * 1024:
        return Response({'detail': '请选择不超过 10 MB 的图片'}, status=400)
    raw = file.read()
    digest = hashlib.sha256(raw).hexdigest()
    file.seek(0)
    idempotency_key = request.headers.get('Idempotency-Key', '')
    if idempotency_key and (len(idempotency_key) != 64 or any(c not in '0123456789abcdef' for c in idempotency_key.lower())):
        return Response({'detail': '上传标识无效，请重新选择图片'}, status=400)
    def prior_receipt():
        prior = Evidence.objects.filter(idempotency_key=idempotency_key).first() if idempotency_key else None
        if prior:
            if prior.job_id != job.pk or prior.content_hash != digest or prior.stage != stage or str(prior.issue_id or '') != str(request.data.get('issue_id') or '') or prior.uploader_id != request.user.pk:
                return Response({'detail': '上传标识已用于其他内容'}, status=409)
            return Response({'id': prior.pk, 'preview': 'available', 'reused': True})
        return None
    prior = prior_receipt()
    if prior is not None:
        return prior
    try:
        raw = file.read()
        image = Image.open(io.BytesIO(raw))
        if image.format not in ("PNG", "JPEG") or image.width * image.height > 16_000_000:
            return Response({"detail": "仅支持不超过 16 MP 的 PNG 或 JPEG 图片"}, status=400)
        image.verify()
        decoded = cv2.imdecode(np.frombuffer(raw, dtype=np.uint8), cv2.IMREAD_COLOR)
        if decoded is None:
            raise ValueError("decode failed")
        height, width = decoded.shape[:2]
        scale = min(1.0, 2048 / max(width, height))
        if scale < 1:
            decoded = cv2.resize(decoded, (round(width * scale), round(height * scale)), interpolation=cv2.INTER_AREA)
        from .vision import edge_image, ALGORITHM
        encoded, _ = edge_image(decoded)
    except (UnidentifiedImageError, OSError, ValueError):
        return Response({"detail": "图片内容无法识别，请重新选择 PNG 或 JPEG 文件"}, status=400)
    original_name = 'photo.png' if image.format == 'PNG' else 'photo.jpg'
    evidence = None
    try:
        with transaction.atomic():
            ProductionJob.objects.filter(pk=job.pk).update(updated_at=F('updated_at'))
            job.refresh_from_db()
            prior = prior_receipt()
            if prior is not None:
                return prior
            if job.status not in ('inspection', 'exception') or (stage == 'inspection' and job.status != 'inspection'):
                return Response({'detail': '当前任务状态不能添加图片'}, status=409)
            if stage in ('before', 'after'):
                issue = ExceptionCase.objects.filter(pk=request.data.get('issue_id'), job=job, status='open').first()
                if issue is None:
                    return Response({'detail': '请选择当前任务的未处理异常'}, status=400)
                inspection = issue.inspection
            evidence = Evidence(job=job, idempotency_key=idempotency_key or None, stage=stage, issue=issue,
                inspection=inspection, uploader=request.user, content_hash=digest, preview_algorithm=ALGORITHM)
            evidence.image.save(original_name, ContentFile(raw), save=False)
            evidence.edge_preview.save('edge.png', ContentFile(encoded), save=False)
            evidence.save()
            AuditEvent.objects.create(workspace=member.workspace, user=request.user, job=job, version=job.version,
                action='evidence.uploaded', object_id=str(evidence.pk), details={'stage': stage, 'inspection_id': evidence.inspection_id, 'issue_id': evidence.issue_id})
    except BaseException:
        if evidence:
            evidence.image.delete(save=False)
            evidence.edge_preview.delete(save=False)
        raise
    return Response({'id': evidence.pk, 'preview': 'available', 'reused': False}, status=201)



@api_view(["GET"])
@permission_classes([IsAuthenticated])
def evidence_preview(request, workspace_id, job_id, evidence_id):
    member = membership(request, workspace_id)
    try:
        evidence = Evidence.objects.select_related("job").get(
            pk=evidence_id, job_id=job_id, job__workspace=member.workspace
        )
    except Evidence.DoesNotExist as exc:
        raise Http404 from exc
    from .vision import edge_image, ALGORITHM
    if evidence.preview_algorithm != ALGORITHM:
        with transaction.atomic():
            evidence = Evidence.objects.select_for_update().get(pk=evidence.pk)
            if evidence.preview_algorithm != ALGORITHM:
                with evidence.image.open('rb') as original:
                    decoded = cv2.imdecode(np.frombuffer(original.read(), dtype=np.uint8), cv2.IMREAD_COLOR)
                png, _ = edge_image(decoded)
                evidence.edge_preview.save('edge-v1.png', ContentFile(png), save=False)
                evidence.preview_algorithm = ALGORITHM
                evidence.save(update_fields=['edge_preview', 'preview_algorithm'])
    return FileResponse(evidence.edge_preview.open("rb"), content_type="image/png")


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def evidence_original(request, workspace_id, job_id, evidence_id):
    member = membership(request, workspace_id)
    try:
        evidence = Evidence.objects.select_related("job").get(
            pk=evidence_id, job_id=job_id, job__workspace=member.workspace
        )
    except Evidence.DoesNotExist as exc:
        raise Http404 from exc
    content_type = mimetypes.guess_type(evidence.image.name)[0] or "application/octet-stream"
    return FileResponse(evidence.image.open("rb"), content_type=content_type)
