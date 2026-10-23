"""Real bearer-token regressions for SEC-02/05/06 and COL-01.

Use API login, not force_authenticate: the 401/403 boundary and continued use
of a previously issued token are precisely what these tests must exercise.
"""
import time
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core import signing
from django.test import TestCase
from rest_framework.test import APIClient

from .models import AuditEvent, Evidence, Membership, ProductionJob, Workspace


class PermissionFoundationTests(TestCase):
    def setUp(self):
        self.owner = self.user("manager")
        self.operator = self.user("worker")
        self.ws = Workspace.objects.create(name="Permission test")
        Membership.objects.create(workspace=self.ws, user=self.owner, role="owner")
        Membership.objects.create(workspace=self.ws, user=self.operator, role="operator")
        self.admin = self.login(self.owner)
        self.worker = self.login(self.operator)
        self.base = f"/api/v1/workspaces/{self.ws.pk}"
        self.job = ProductionJob.objects.create(workspace=self.ws, part_name="Bracket", printer="A1", quantity=1)

    def user(self, name):
        return get_user_model().objects.create_user(username=name, password="test-password-123")

    def login(self, user):
        client = APIClient()
        response = client.post("/api/v1/auth/login/", {"username": user.username, "password": "test-password-123"}, format="json")
        self.assertEqual(response.status_code, 200)
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        return client

    def test_member_self_flag_uses_authenticated_user_not_display_name(self):
        rows = self.admin.get(f"{self.base}/members/").data
        self.assertEqual([row['id'] for row in rows if row['is_self']], [self.owner.pk])
        rows = self.worker.get(f"{self.base}/members/").data
        self.assertEqual([row['id'] for row in rows if row['is_self']], [self.operator.pk])

    def test_missing_invalid_expired_or_inactive_identity_is_401(self):
        for token in (None, "not-a-signed-token"):
            client = APIClient()
            if token:
                client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
            response = client.get(f"{self.base}/jobs/")
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response["WWW-Authenticate"], "Bearer")
        with patch("django.core.signing.time.time", return_value=time.time() - 4000):
            expired = signing.dumps({"uid": self.owner.pk}, salt="linesight-access", compress=True)
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION=f"Bearer {expired}")
        self.assertEqual(client.get(f"{self.base}/jobs/").status_code, 401)
        self.operator.is_active = False
        self.operator.save(update_fields=["is_active"])
        self.assertEqual(self.worker.get(f"{self.base}/jobs/").status_code, 401)

    def test_downgrade_old_token_requires_reauth_then_viewer_cannot_write(self):
        response = self.admin.patch(f"{self.base}/members/worker/", {"role": "viewer"}, format="json")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.worker.get(f"{self.base}/jobs/").status_code, 401)
        self.worker = self.login(self.operator)
        self.assertEqual(self.worker.get(f"{self.base}/jobs/").status_code, 200)
        paths = [
            ("post", "/jobs/", {"part_name": "X", "printer": "A1", "quantity": 1}),
            ("patch", f"/jobs/{self.job.pk}/", {"status": "printing"}),
            ("post", f"/jobs/{self.job.pk}/inspection/", {"verdict": "pass"}),
            ("post", f"/jobs/{self.job.pk}/exceptions/", {"note": "fail"}),
            ("post", f"/jobs/{self.job.pk}/evidence/", {}),
            ("post", "/legacy-inspections/", {"records": []}),
            ("post", "/invite/", {}),
            ("post", "/printer-profiles/", {}),
            ("patch", "/members/manager/", {"role": "viewer"}),
        ]
        for method, path, data in paths:
            with self.subTest(path=path):
                response = getattr(self.worker, method)(self.base + path, data, format="json")
                self.assertEqual(response.status_code, 403)
                self.assertNotIn("WWW-Authenticate", response)
        self.job.refresh_from_db()
        self.assertEqual(self.job.status, "queued")

    def test_removed_member_old_token_loses_private_resources_but_other_team_survives(self):
        other = Workspace.objects.create(name="Other")
        Membership.objects.create(workspace=other, user=self.operator, role="owner")
        evidence = Evidence.objects.create(job=self.job, image="private.png", edge_preview="edge.png")
        response = self.admin.delete(f"{self.base}/members/worker/")
        self.assertEqual(response.status_code, 200)
        for path in ("/jobs/", "/members/", "/legacy-inspections/",
                     f"/jobs/{self.job.pk}/evidence/{evidence.pk}/original/",
                     f"/jobs/{self.job.pk}/evidence/{evidence.pk}/preview/"):
            self.assertEqual(self.worker.get(self.base + path).status_code, 404)
        self.assertEqual(self.worker.get(f"/api/v1/workspaces/{other.pk}/jobs/").status_code, 200)
        self.assertEqual([row["id"] for row in self.worker.get("/api/v1/workspaces/").data], [other.pk])
        self.assertTrue(AuditEvent.objects.filter(workspace=self.ws, action="member.removed", user=self.owner).exists())

    def test_leave_and_last_admin_protection(self):
        self.assertEqual(self.admin.post(f"{self.base}/leave/").status_code, 409)
        self.assertEqual(self.admin.delete(f"{self.base}/members/manager/").status_code, 409)
        self.assertEqual(self.admin.patch(f"{self.base}/members/manager/", {"role": "viewer"}, format="json").status_code, 409)
        self.assertEqual(self.worker.patch(f"{self.base}/members/manager/", {"role": "operator"}, format="json").status_code, 403)
        self.assertEqual(self.admin.patch(f"{self.base}/members/worker/", {"role": "owner"}, format="json").status_code, 200)
        self.assertEqual(self.admin.post(f"{self.base}/leave/").status_code, 204)
        self.assertEqual(self.admin.get(f"{self.base}/jobs/").status_code, 404)
        self.worker = self.login(self.operator)
        self.assertEqual(self.worker.post(f"{self.base}/leave/").status_code, 409)

    def test_foreign_workspace_and_invalid_role_cannot_change_members(self):
        stranger = self.login(self.user("stranger"))
        self.assertEqual(stranger.delete(f"{self.base}/members/worker/").status_code, 404)
        self.assertEqual(self.admin.patch(f"{self.base}/members/worker/", {"role": "root"}, format="json").status_code, 400)
        self.assertEqual(Membership.objects.get(workspace=self.ws, user=self.operator).role, "operator")
