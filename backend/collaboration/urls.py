from django.urls import path
from . import api

urlpatterns = [
    path("auth/register/", api.register), path("auth/login/", api.login),
    path("workspaces/", api.workspaces), path("workspaces/create/", api.create_workspace),
    path("workspaces/<int:workspace_id>/members/", api.members),
    path("workspaces/<int:workspace_id>/printer-profiles/", api.printer_profiles),
    path("workspaces/<int:workspace_id>/legacy-inspections/", api.legacy_inspections),
    path("workspaces/redeem/", api.redeem), path("workspaces/<int:workspace_id>/invite/", api.invite),
    path("workspaces/<int:workspace_id>/jobs/", api.jobs),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/", api.update_job),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/inspection/", api.quality_decision),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/", api.upload_evidence),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/<int:evidence_id>/preview/", api.evidence_preview),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/<int:evidence_id>/original/", api.evidence_original),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/exceptions/", api.create_exception),
    path("workspaces/<int:workspace_id>/exceptions/<int:case_id>/resolve/", api.resolve_exception),
]
