import secrets
import hashlib
import uuid
from django.conf import settings
from django.db import models
from django.utils import timezone


def evidence_upload_path(instance, filename):
    return f"workspace-{instance.job.workspace_id}/evidence/{filename}"


def preview_upload_path(instance, filename):
    return f"workspace-{instance.job.workspace_id}/previews/{filename}"


class Workspace(models.Model):
    dispatch_enabled = models.BooleanField(default=False)
    name = models.CharField(max_length=100)
    kind = models.CharField(max_length=12, default="team", choices=[("personal", "Personal"), ("team", "Team"), ("demo", "Demo")])
    created_at = models.DateTimeField(auto_now_add=True)


class Membership(models.Model):
    OWNER = "owner"
    MANAGER = "manager"
    OPERATOR = "operator"
    VIEWER = "viewer"
    ROLES = [(OWNER, "Owner"), (MANAGER, "Manager"), (OPERATOR, "Operator"), (VIEWER, "Viewer")]
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    role = models.CharField(max_length=12, choices=ROLES)
    token_not_before = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["workspace", "user"], name="one_workspace_membership")]


class CloudIdentity(models.Model):
    issuer = models.CharField(max_length=300)
    subject = models.CharField(max_length=200)
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="cloud_identity")
    is_demo = models.BooleanField(default=False)
    home_workspace = models.ForeignKey(Workspace, on_delete=models.SET_NULL, null=True)
    display_name = models.CharField(max_length=100, blank=True)
    avatar_seed = models.CharField(max_length=64, blank=True)
    job_title = models.CharField(max_length=80, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["issuer", "subject"], name="unique_oidc_identity")]


class Invitation(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="invitations")
    token_hash = models.CharField(max_length=64, unique=True)
    role = models.CharField(max_length=12, choices=Membership.ROLES)
    expires_at = models.DateTimeField()
    redeemed_at = models.DateTimeField(null=True, blank=True)

    @staticmethod
    def digest(token):
        return hashlib.sha256(token.encode()).hexdigest()


class InvitationRedemption(models.Model):
    invitation = models.ForeignKey(Invitation, on_delete=models.CASCADE, related_name="redemptions")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["invitation", "user"], name="unique_invitation_redeemer")]

class ProductionJob(models.Model):
    batch_code = models.CharField(max_length=80, blank=True)
    assignee = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='assigned_jobs')
    template = models.ForeignKey('CheckTemplate', on_delete=models.PROTECT, null=True, blank=True)
    tracking_mode = models.CharField(max_length=10, default='batch')
    serial_numbers = models.JSONField(default=list, blank=True)
    version = models.PositiveIntegerField(default=1)
    STATUSES = [(s, s) for s in ("queued", "printing", "inspection", "exception", "closed")]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="jobs")
    part_name = models.CharField(max_length=100)
    printer = models.CharField(max_length=80)
    quantity = models.PositiveIntegerField()
    note = models.CharField(max_length=500, blank=True)
    status = models.CharField(max_length=16, choices=STATUSES, default="queued")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class JobRequest(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    request_id = models.CharField(max_length=64)
    request_hash = models.CharField(max_length=64)
    job = models.OneToOneField(ProductionJob, on_delete=models.CASCADE)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["workspace", "request_id"], name="unique_workspace_job_request")]


class PrinterProfile(models.Model):
    revision = models.PositiveIntegerField(default=1)
    default_template = models.ForeignKey("CheckTemplate", on_delete=models.PROTECT, null=True, blank=True, related_name="printer_profiles")
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="printer_profiles")
    name = models.CharField(max_length=80)
    version = models.CharField(max_length=40)
    source_url = models.URLField(max_length=300)
    note = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["workspace", "name"], name="unique_workspace_printer_profile")]


class JobProfileMetadata(models.Model):
    job = models.OneToOneField(ProductionJob, on_delete=models.CASCADE, related_name="profile_metadata")
    version = models.CharField(max_length=40)
    source_url = models.URLField(max_length=300)


class LegacyInspection(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="legacy_inspections")
    source_id = models.CharField(max_length=64)
    payload = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["workspace", "source_id"], name="unique_workspace_legacy_record")]



class ExceptionCase(models.Model):
    inspection = models.ForeignKey('QualityInspection', on_delete=models.PROTECT, null=True, blank=True, related_name='issues')
    category = models.CharField(max_length=30, default='other')
    severity = models.CharField(max_length=12, default='major')
    creator = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE, related_name="exceptions")
    note = models.CharField(max_length=500)
    status = models.CharField(max_length=12, default="open")
    assignee = models.CharField(max_length=100, blank=True)
    resolution = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)


class QualityInspection(models.Model):
    round_no = models.PositiveIntegerField(default=1)
    inspected_qty = models.PositiveIntegerField(null=True, blank=True)
    pass_qty = models.PositiveIntegerField(null=True, blank=True)
    fail_qty = models.PositiveIntegerField(null=True, blank=True)
    scrap_qty = models.PositiveIntegerField(null=True, blank=True)
    template_snapshot = models.JSONField(default=dict, blank=True)
    answers = models.JSONField(default=list, blank=True)
    serial_results = models.JSONField(default=dict, blank=True)
    VERDICTS = [("pass", "Pass"), ("fail", "Fail")]
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE, related_name="quality_inspections")
    inspector = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)
    verdict = models.CharField(max_length=8, choices=VERDICTS)
    note = models.CharField(max_length=500, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class Evidence(models.Model):
    inspection = models.ForeignKey(QualityInspection, on_delete=models.PROTECT, null=True, blank=True, related_name='photos')
    issue = models.ForeignKey(ExceptionCase, on_delete=models.PROTECT, null=True, blank=True, related_name='photos')
    stage = models.CharField(max_length=12, default='inspection')
    uploader = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    content_hash = models.CharField(max_length=64, blank=True)
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE, related_name="evidence")
    image = models.ImageField(upload_to=evidence_upload_path)
    edge_preview = models.ImageField(upload_to=preview_upload_path)
    preview_algorithm = models.CharField(max_length=48, blank=True, default='')
    idempotency_key = models.CharField(max_length=64, unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class AuditEvent(models.Model):
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE, null=True, blank=True, related_name="events")
    version = models.PositiveIntegerField(null=True, blank=True)
    details = models.JSONField(default=dict, blank=True)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)
    action = models.CharField(max_length=60)
    object_id = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)


class JobMutation(models.Model):
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE, related_name="mutations")
    key = models.CharField(max_length=64)
    request_hash = models.CharField(max_length=64)
    result = models.JSONField()
    status_code = models.PositiveSmallIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["job", "key"], name="unique_job_mutation_key")]


class CheckTemplate(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, null=True, blank=True)
    name = models.CharField(max_length=100)
    version = models.PositiveIntegerField(default=1)
    items = models.JSONField(default=list)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['workspace', 'name', 'version'], name='unique_template_version')]


class PieceSerial(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE)
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE)
    serial = models.CharField(max_length=100)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['workspace', 'serial'], name='unique_workspace_piece_serial')]


class NotificationReceipt(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    job = models.ForeignKey(ProductionJob, on_delete=models.CASCADE)
    version = models.PositiveIntegerField()
    read_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['user', 'job'], name='unique_user_job_notice')]


class NfcCredential(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    card_hash = models.CharField(max_length=64)
    public_key = models.CharField(max_length=64)
    label = models.CharField(max_length=80, default='NFC')
    technology = models.CharField(max_length=160, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    revoked_at = models.DateTimeField(null=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['card_hash','public_key'], name='unique_nfc_device_card')]


class NfcChallenge(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    credential = models.ForeignKey(NfcCredential, on_delete=models.CASCADE, null=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    nonce = models.CharField(max_length=64)
    action = models.CharField(max_length=12)
    payload = models.JSONField(default=dict)
    expires_at = models.DateTimeField()
    consumed_at = models.DateTimeField(null=True)


class NfcSession(models.Model):
    credential = models.ForeignKey(NfcCredential, on_delete=models.CASCADE)
    sid = models.CharField(max_length=200, unique=True)
    refresh_hash = models.CharField(max_length=64, unique=True)
    revoked_at = models.DateTimeField(null=True)
    created_at = models.DateTimeField(auto_now_add=True)


class WorkspaceBulletin(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name="bulletins")
    source_key = models.CharField(max_length=100, unique=True)
    kind = models.CharField(max_length=16, default="notice")
    title = models.CharField(max_length=150)
    body = models.TextField()
    published_at = models.DateTimeField(db_index=True)
    job = models.ForeignKey(ProductionJob, null=True, blank=True, on_delete=models.SET_NULL)
    template = models.ForeignKey(CheckTemplate, null=True, blank=True, on_delete=models.SET_NULL)
    read_by = models.ManyToManyField(settings.AUTH_USER_MODEL, blank=True)
