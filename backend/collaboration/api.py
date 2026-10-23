import io
import json
import hashlib
import re
import mimetypes
import secrets
from datetime import timedelta
from PIL import Image, UnidentifiedImageError
import cv2
import numpy as np
from django.contrib.auth import authenticate, get_user_model
from django.core import signing
from django.core.files.base import ContentFile
from django.db import transaction
from django.http import Http404
from django.http import FileResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import JSONParser, MultiPartParser, FormParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from .models import AuditEvent, ExceptionCase, Evidence, Invitation, InvitationRedemption, JobProfileMetadata, JobRequest, LegacyInspection, Membership, PrinterProfile, ProductionJob, QualityInspection, Workspace


def membership(request, workspace_id, write=False):
    try:
        member = Membership.objects.select_related("workspace").get(workspace_id=workspace_id, user=request.user)
    except Membership.DoesNotExist as exc:
        raise Http404 from exc
    if write and member.role == Membership.VIEWER:
        raise PermissionDenied("当前成员仅可查看")
    return member


@api_view(["POST"])
@permission_classes([AllowAny])
def register(request):
    username = str(request.data.get("username", "")).strip().lower()
    password = str(request.data.get("password", ""))
    if not re.fullmatch(r"[a-z0-9_.-]{3,32}", username) or not 12 <= len(password) <= 128:
        return Response({"detail": "用户名至少 3 位，密码至少 12 位"}, status=400)
    User = get_user_model()
    if User.objects.filter(username=username).exists():
        return Response({"detail": "用户名已存在"}, status=409)
    user = User.objects.create_user(username=username, password=password)
    return Response({"id": user.pk, "username": user.username}, status=201)


@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    user = authenticate(username=request.data.get("username", ""), password=request.data.get("password", ""))
    if user is None:
        return Response({"detail": "用户名或密码错误"}, status=401)
    token = signing.dumps({"uid": user.pk}, salt="linesight-access", compress=True)
    return Response({"access": token, "expires_in": 3600})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def create_workspace(request):
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
    return Response([{"id": m.workspace_id, "name": m.workspace.name, "role": m.role} for m in rows])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def members(request, workspace_id):
    member = membership(request, workspace_id)
    rows = Membership.objects.filter(workspace=member.workspace).select_related("user").order_by("user__username")
    return Response([{"username": row.user.username, "role": row.role} for row in rows])


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
            target.save(update_fields=["role"])
            action = "member.role"
        AuditEvent.objects.create(workspace=member.workspace, user=request.user,
            action=action, object_id=str(target.user_id))
    return Response({"username": username, "previous_role": before,
                     "role": role if request.method == "PATCH" else None})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def leave_workspace(request, workspace_id):
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


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def printer_profiles(request, workspace_id):
    member = membership(request, workspace_id, write=request.method == "POST")
    if request.method == "GET":
        overrides = PrinterProfile.objects.filter(workspace=member.workspace).order_by("name")
        return Response(STARTER_PROFILES + [{"id": f"workspace:{p.pk}", "name": p.name, "version": p.version,
            "source": p.source_url, "note": p.note, "override": True} for p in overrides])
    if member.role != Membership.OWNER:
        raise PermissionDenied("仅工作区所有者可维护打印机配置")
    name = str(request.data.get("name", "")).strip()
    version = str(request.data.get("version", "")).strip()
    source = str(request.data.get("source", "")).strip()
    note = str(request.data.get("note", "")).strip()
    if not name or len(name) > 80 or not version or len(version) > 40 or not source.startswith("https://") or len(note) > 300:
        return Response({"detail": "请填写配置名称、版本和 HTTPS 来源"}, status=400)
    profile, created = PrinterProfile.objects.update_or_create(workspace=member.workspace, name=name,
        defaults={"version": version, "source_url": source, "note": note})
    return Response({"id": f"workspace:{profile.pk}", "name": profile.name, "version": profile.version,
        "source": profile.source_url, "note": profile.note, "override": True}, status=201 if created else 200)


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
                         "passed": row.payload.get("passed", False), "sample": row.payload.get("sample", False)}
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
    if role not in (Membership.OPERATOR, Membership.VIEWER):
        return Response({"detail": "邀请角色无效"}, status=400)
    token = secrets.token_urlsafe(24)
    Invitation.objects.create(workspace=member.workspace, token_hash=Invitation.digest(token), role=role,
                              expires_at=timezone.now() + timedelta(hours=48))
    return Response({"code": token, "role": role, "expires_in": 172800}, status=201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def redeem(request):
    token = request.data.get("code", "")
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
        return Response([job_json(x) for x in member.workspace.jobs.order_by("-created_at")])
    d = request.data
    part, printer, quantity = str(d.get("part_name", "")).strip(), str(d.get("printer", "")).strip(), d.get("quantity")
    if not part or len(part) > 100 or not printer or len(printer) > 80 or not isinstance(quantity, int) or not 1 <= quantity <= 999:
        return Response({"detail": "任务名称、设备和数量不符合要求"}, status=400)
    profile_id = str(d.get("profile_id", ""))
    profile = None
    if profile_id.startswith("starter:"):
        profile = next((item for item in STARTER_PROFILES if item["id"] == profile_id), None)
    elif profile_id.startswith("workspace:"):
        try:
            profile = PrinterProfile.objects.get(pk=int(profile_id.split(":", 1)[1]), workspace=member.workspace)
        except (ValueError, PrinterProfile.DoesNotExist):
            profile = None
        if profile:
            profile = {"name": profile.name, "version": profile.version, "source": profile.source_url}
    if profile_id and profile is None:
        return Response({"detail": "打印机配置不存在或不属于此工作区"}, status=404)
    if profile:
        printer = profile["name"]
    request_id = request.headers.get("Idempotency-Key", "")
    note = str(d.get("note", ""))[:500]
    payload = json.dumps({"part_name": part, "printer": printer, "quantity": quantity, "note": note,
                          "profile_id": profile_id}, sort_keys=True, ensure_ascii=False)
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
        job = ProductionJob.objects.create(workspace=member.workspace, part_name=part, printer=printer,
                                           quantity=quantity, note=note)
        if profile:
            JobProfileMetadata.objects.create(job=job, version=profile["version"], source_url=profile["source"])
        if request_id:
            JobRequest.objects.create(workspace=member.workspace, request_id=request_id, request_hash=payload_hash, job=job)
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, action="job.created", object_id=str(job.pk))
    return Response(job_json(job), status=201)


def job_json(job):
    profile = getattr(job, "profile_metadata", None)
    return {"id": str(job.pk), "part_name": job.part_name, "printer": job.printer, "quantity": job.quantity,
            "note": job.note, "status": job.status, "created_at": job.created_at.isoformat(),
            "profile_version": profile.version if profile else "", "profile_source": profile.source_url if profile else "",
            "exceptions": [{"id": x.pk, "note": x.note, "status": x.status, "assignee": x.assignee,
                            "resolution": x.resolution} for x in job.exceptions.order_by("-created_at")],
            "inspections": [{"id": x.pk, "verdict": x.verdict, "note": x.note,
                             "created_at": x.created_at.isoformat()} for x in job.quality_inspections.order_by("-created_at")],
            "evidence": [{"id": x.pk, "created_at": x.created_at.isoformat()} for x in job.evidence.order_by("-created_at")]}


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def quality_decision(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    if job.status != "inspection":
        return Response({"detail": "任务当前不能登记质检结果"}, status=409)
    verdict = request.data.get("verdict")
    if verdict not in ("pass", "fail"):
        return Response({"detail": "请选择合格或异常"}, status=400)
    note = str(request.data.get("note", "")).strip()[:500]
    assignee = str(request.data.get("assignee", "")).strip()[:100]
    if verdict == "fail" and not note:
        return Response({"detail": "请描述需要复核的问题"}, status=400)
    with transaction.atomic():
        check = QualityInspection.objects.create(job=job, inspector=request.user, verdict=verdict, note=note)
        if verdict == "pass":
            job.status = "closed"
        else:
            issue = ExceptionCase.objects.create(job=job, note=note, assignee=assignee)
            job.status = "exception"
        job.save(update_fields=["status", "updated_at"])
        AuditEvent.objects.create(workspace=member.workspace, user=request.user,
                                  action=f"inspection.{verdict}", object_id=str(check.pk))
    return Response(job_json(job), status=201)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def update_job(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    next_status = request.data.get("status")
    transitions = {"queued": {"printing"}, "printing": {"inspection"}, "inspection": set(),
                   "exception": {"inspection", "closed"}, "closed": set()}
    if next_status not in transitions[job.status]:
        return Response({"detail": "任务状态无法这样变更"}, status=409)
    job.status = next_status
    job.save(update_fields=["status", "updated_at"])
    AuditEvent.objects.create(workspace=member.workspace, user=request.user, action="job.status", object_id=str(job.pk))
    return Response(job_json(job))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser])
def upload_evidence(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    if job.status != "inspection":
        return Response({"detail": "任务进入质检后才能添加图片"}, status=409)
    file = request.FILES.get("image")
    if file is None or file.size > 10 * 1024 * 1024:
        return Response({"detail": "请选择不超过 10 MB 的图片"}, status=400)
    idempotency_key = request.headers.get("Idempotency-Key", "")
    if idempotency_key:
        if len(idempotency_key) != 64 or any(c not in "0123456789abcdef" for c in idempotency_key.lower()):
            return Response({"detail": "上传标识无效，请重新选择图片"}, status=400)
        prior = Evidence.objects.filter(job=job, idempotency_key=idempotency_key).first()
        if prior:
            return Response({"id": prior.pk, "preview": "available", "verdict": "由操作人员确认", "reused": True}, status=200)
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
        blurred = cv2.GaussianBlur(decoded, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)
        # Keep the reference legible in the app's bright visual system.
        preview = np.full((*edges.shape, 3), 255, dtype=np.uint8)
        preview[edges > 0] = (52, 120, 246)
        ok, encoded = cv2.imencode(".png", cv2.cvtColor(preview, cv2.COLOR_RGB2BGR))
        if not ok:
            raise ValueError("preview failed")
    except (UnidentifiedImageError, OSError, ValueError):
        return Response({"detail": "图片内容无法识别，请重新选择 PNG 或 JPEG 文件"}, status=400)
    original_name = file.name.rsplit("/", 1)[-1].rsplit("\\", 1)[-1][:120]
    evidence = Evidence(job=job, idempotency_key=idempotency_key or None)
    evidence.image.save(original_name, ContentFile(raw), save=False)
    evidence.edge_preview.save("edge.png", ContentFile(encoded.tobytes()), save=False)
    evidence.save()
    return Response({"id": evidence.pk, "preview": "available", "verdict": "由操作人员确认", "reused": False}, status=201)


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


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def create_exception(request, workspace_id, job_id):
    member = membership(request, workspace_id, write=True)
    try:
        job = member.workspace.jobs.get(pk=job_id)
    except ProductionJob.DoesNotExist as exc:
        raise Http404 from exc
    if job.status != "inspection":
        return Response({"detail": "任务进入质检后才能提交异常"}, status=409)
    note = str(request.data.get("note", "")).strip()
    if not note:
        return Response({"detail": "请描述需要复核的问题"}, status=400)
    with transaction.atomic():
        check = QualityInspection.objects.create(job=job, inspector=request.user, verdict="fail", note=note[:500])
        case = ExceptionCase.objects.create(job=job, note=note[:500], assignee=str(request.data.get("assignee", ""))[:100])
        job.status = "exception"
        job.save(update_fields=["status", "updated_at"])
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, action="exception.created", object_id=str(case.pk))
        AuditEvent.objects.create(workspace=member.workspace, user=request.user, action="inspection.fail", object_id=str(check.pk))
    return Response({"id": case.pk, "status": case.status, "note": case.note, "assignee": case.assignee}, status=201)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def resolve_exception(request, workspace_id, case_id):
    member = membership(request, workspace_id, write=True)
    try:
        case = ExceptionCase.objects.select_related("job").get(pk=case_id, job__workspace=member.workspace)
    except ExceptionCase.DoesNotExist as exc:
        raise Http404 from exc
    resolution = str(request.data.get("resolution", "")).strip()
    if not resolution:
        return Response({"detail": "请填写处理结果"}, status=400)
    next_status = request.data.get("next_status", "inspection")
    if next_status not in ("inspection", "closed"):
        return Response({"detail": "处理后任务状态无效"}, status=400)
    case.status, case.resolution, case.resolved_at = "resolved", resolution[:500], timezone.now()
    case.save(update_fields=["status", "resolution", "resolved_at"])
    case.job.status = next_status
    case.job.save(update_fields=["status", "updated_at"])
    AuditEvent.objects.create(workspace=member.workspace, user=request.user, action="exception.resolved", object_id=str(case.pk))
    return Response({"status": case.status, "job_status": case.job.status})
