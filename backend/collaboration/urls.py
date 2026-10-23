from django.urls import path
from . import api, workflow, product

urlpatterns = [
    path("auth/register/", api.register), path("auth/login/", api.login),
    path("auth/me/", api.account),
    path("workspaces/", api.workspaces), path("workspaces/create/", api.create_workspace),
    path("workspaces/<int:workspace_id>/members/", api.members),
    path("workspaces/<int:workspace_id>/members/<str:username>/", api.manage_member),
    path("workspaces/<int:workspace_id>/leave/", api.leave_workspace),
    path("workspaces/<int:workspace_id>/printer-profiles/", api.printer_profiles),
    path("workspaces/<int:workspace_id>/legacy-inspections/", api.legacy_inspections),
    path("workspaces/redeem/", api.redeem), path("workspaces/<int:workspace_id>/invite/", api.invite),
    path("workspaces/<int:workspace_id>/jobs/", api.jobs),
    path('workspaces/<int:workspace_id>/templates/', product.templates),
    path('workspaces/<int:workspace_id>/records/', product.records),
    path('workspaces/<int:workspace_id>/metrics/', product.metrics),
    path('workspaces/<int:workspace_id>/report/', product.report),
    path('workspaces/<int:workspace_id>/notifications/', product.notifications),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/", workflow.task),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/history/", workflow.history),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/inspection/", workflow.inspect),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/", api.upload_evidence),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/<int:evidence_id>/preview/", api.evidence_preview),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/evidence/<int:evidence_id>/original/", api.evidence_original),
    path("workspaces/<int:workspace_id>/jobs/<uuid:job_id>/exceptions/", workflow.exception),
    path("workspaces/<int:workspace_id>/exceptions/<int:case_id>/resolve/", workflow.resolve),
]
