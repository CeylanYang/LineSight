import io
import json
import time
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import URLError

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from .models import CloudIdentity, Membership, Workspace


@override_settings(LINESIGHT_OIDC_ISSUER="https://identity.test/realms/linesight",
                   LINESIGHT_OIDC_CLIENT_SECRET="test-confidential-client")
class OidcApiTests(TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    def setUp(self):
        self.client = APIClient()
        self.jwks = patch("collaboration.oidc.jwks_client").start()
        self.jwks.return_value.get_signing_key_from_jwt.return_value = SimpleNamespace(key=self.key.public_key())
        self.introspection = patch("collaboration.oidc.urlopen").start()
        self.addCleanup(patch.stopall)
        self.active_subject = "person-1"
        self.introspection.side_effect = lambda *args, **kwargs: io.BytesIO(json.dumps({"active": True, "sub": self.active_subject}).encode())

    def token(self, **changes):
        now = time.time()
        claims = {"iss": "https://identity.test/realms/linesight", "sub": "person-1", "aud": "linesight-api",
                  "azp": "linesight-android", "exp": now + 300, "iat": now - 1,
                  "preferred_username": "engineer", "name": "工程师", "realm_access": {"roles": []}}
        claims.update(changes)
        return jwt.encode(claims, self.key, algorithm="RS256", headers={"kid": "test-key"})

    def sign_in(self, **changes):
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + self.token(**changes))

    def test_verified_cloud_identity_gets_private_home_without_legacy_account_linking(self):
        legacy = get_user_model().objects.create_user(username="engineer", password="local-password-123")
        self.sign_in()
        response = self.client.get("/api/v1/auth/me/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["username"], "engineer")
        identity = CloudIdentity.objects.get(subject="person-1")
        self.assertNotEqual(identity.user_id, legacy.pk)
        self.assertFalse(identity.user.has_usable_password())
        self.assertEqual(identity.home_workspace.kind, "personal")
        self.assertEqual(self.client.get("/api/v1/workspaces/").data[0]["role"], "owner")
        self.client.get("/api/v1/auth/me/")
        self.assertEqual(CloudIdentity.objects.count(), 1)
        changed = self.client.patch("/api/v1/auth/me/", {"display_name": "Quality Engineer"}, format="json")
        self.assertEqual(changed.data["display_name"], "Quality Engineer")

    def test_invalid_signature_issuer_audience_expiry_or_client_never_provisions(self):
        invalid = [{"iss": "https://attacker.invalid"}, {"aud": "another-api"}, {"exp": time.time() - 60},
                   {"azp": "untrusted-client"}, {"azp": "linesight-demo"}]
        for change in invalid:
            with self.subTest(change=change):
                self.sign_in(**change)
                self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
        forged = self.token().split(".")
        forged[2] = "A" * len(forged[2])
        self.client.credentials(HTTP_AUTHORIZATION="Bearer " + ".".join(forged))
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
        self.assertFalse(CloudIdentity.objects.exists())
        self.introspection.assert_not_called()

    def test_provider_revoked_session_is_401_and_outage_is_recoverable_503(self):
        self.sign_in()
        self.introspection.side_effect = lambda *args, **kwargs: io.BytesIO(b'{"active":false}')
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 401)
        self.introspection.side_effect = URLError("provider unavailable")
        self.assertEqual(self.client.get("/api/v1/auth/me/").status_code, 503)
        self.assertFalse(CloudIdentity.objects.exists())

    def test_demo_identity_is_restricted_even_with_accidental_foreign_membership(self):
        self.sign_in(azp="linesight-demo", realm_access={"roles": ["demo"]})
        me = self.client.get("/api/v1/auth/me/")
        self.assertTrue(me.data["is_demo"])
        identity = CloudIdentity.objects.get(subject="person-1")
        own = identity.home_workspace
        self.assertEqual(own.kind, "demo")
        foreign = Workspace.objects.create(name="Private customer")
        Membership.objects.create(workspace=foreign, user=identity.user, role="owner")
        self.assertEqual([w["id"] for w in self.client.get("/api/v1/workspaces/").data], [own.pk])
        self.assertEqual(self.client.get(f"/api/v1/workspaces/{foreign.pk}/jobs/").status_code, 404)
        self.assertEqual(self.client.post("/api/v1/workspaces/create/", {"name": "Escape"}, format="json").status_code, 403)
        self.assertEqual(self.client.post("/api/v1/workspaces/redeem/", {"code": "anything"}, format="json").status_code, 403)
        self.assertEqual(self.client.post(f"/api/v1/workspaces/{own.pk}/leave/").status_code, 403)
        self.assertEqual(self.client.patch("/api/v1/auth/me/", {"display_name": "Changed"}, format="json").status_code, 403)
        job = self.client.post(f"/api/v1/workspaces/{own.pk}/jobs/", {"part_name": "Demo", "printer": "A1", "quantity": 1}, format="json")
        self.assertEqual(job.status_code, 201)

    def test_legacy_login_and_registration_retire_when_oidc_is_enabled(self):
        self.assertEqual(self.client.post("/api/v1/auth/login/", {}, format="json").status_code, 410)
        self.assertEqual(self.client.post("/api/v1/auth/register/", {}, format="json").status_code, 410)

    def test_new_identity_with_same_username_cannot_take_another_person_home(self):
        self.sign_in()
        first = self.client.get("/api/v1/auth/me/").data
        self.active_subject = "person-2"
        self.sign_in(sub="person-2")
        second = self.client.get("/api/v1/auth/me/").data
        self.assertNotEqual(first["id"], second["id"])
        self.assertNotEqual(first["home_workspace_id"], second["home_workspace_id"])
