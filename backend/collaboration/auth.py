from django.contrib.auth import get_user_model
from django.core import signing
from django.conf import settings
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed


class BearerAuthentication(BaseAuthentication):
    def authenticate_header(self, request):
        # DRF otherwise turns AuthenticationFailed into 403.
        return "Bearer"

    def authenticate(self, request):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        if getattr(settings, "LINESIGHT_OIDC_ISSUER", ""):
            from .oidc import resolve_identity, verify_access_token
            payload = verify_access_token(header[7:])
            identity = resolve_identity(payload)
            return identity.user, payload
        try:
            payload = signing.loads(header[7:], salt="linesight-access", max_age=3600)
            user = get_user_model().objects.get(pk=payload["uid"], is_active=True)
        except Exception as exc:
            raise AuthenticationFailed("登录状态无效或已过期") from exc
        return user, payload
