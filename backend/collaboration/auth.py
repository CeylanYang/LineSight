from django.contrib.auth import get_user_model
from django.core import signing
from rest_framework.authentication import BaseAuthentication
from rest_framework.exceptions import AuthenticationFailed


class BearerAuthentication(BaseAuthentication):
    def authenticate(self, request):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return None
        try:
            payload = signing.loads(header[7:], salt="linesight-access", max_age=3600)
            user = get_user_model().objects.get(pk=payload["uid"], is_active=True)
        except Exception as exc:
            raise AuthenticationFailed("登录状态无效或已过期") from exc
        return user, None
