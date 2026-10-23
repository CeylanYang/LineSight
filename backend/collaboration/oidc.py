"""Keycloak OIDC verification through maintained PyJWT and provider introspection."""
import hashlib
import json
import uuid
from functools import lru_cache
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from rest_framework.exceptions import APIException, AuthenticationFailed

from .models import CloudIdentity, Membership, Workspace


class IdentityServiceUnavailable(APIException):
    status_code = 503
    default_detail = "登录服务暂不可用，请稍后重试"


@lru_cache(maxsize=4)
def jwks_client(uri):
    return jwt.PyJWKClient(uri, cache_jwk_set=True, lifespan=300, timeout=5)


def verify_access_token(token, *, require_nfc_session=True):
    issuer = settings.LINESIGHT_OIDC_ISSUER.rstrip("/")
    try:
        key = jwks_client(getattr(settings, "LINESIGHT_OIDC_JWKS_URL", issuer + "/protocol/openid-connect/certs")).get_signing_key_from_jwt(token)
        claims = jwt.decode(token, key.key, algorithms=["RS256"], issuer=issuer,
            audience="linesight-api", leeway=5,
            options={"require": ["exp", "iat", "iss", "aud", "sub"]})
        if claims.get("azp") not in ("linesight-android", "linesight-demo", "linesight-nfc"):
            raise jwt.InvalidTokenError("Unexpected authorized party")
        realm_access = claims.get("realm_access", {})
        if not isinstance(realm_access, dict) or not isinstance(realm_access.get("roles", []), list):
            raise jwt.InvalidTokenError("Invalid realm roles")
        if not isinstance(claims["sub"], str) or not claims["sub"] or len(claims["sub"]) > 200:
            raise jwt.InvalidTokenError("Invalid subject")
        is_demo = "demo" in realm_access.get("roles", [])
        if claims["azp"] == "linesight-demo" and not is_demo:
            raise jwt.InvalidTokenError("Demo client requires demo identity")
    except jwt.PyJWKClientConnectionError as exc:
        raise IdentityServiceUnavailable() from exc
    except jwt.PyJWTError as exc:
        raise AuthenticationFailed("登录状态无效或已过期") from exc
    # Signature validation alone cannot revoke a logged-out session immediately.
    # Introspection is deliberately not cached; transient IdP failures are 503.
    endpoint = getattr(settings, "LINESIGHT_OIDC_INTROSPECTION_URL", issuer + "/protocol/openid-connect/token/introspect")
    body = urlencode({"client_id": "linesight-api", "client_secret": settings.LINESIGHT_OIDC_CLIENT_SECRET,
                      "token": token, "token_type_hint": "access_token"}).encode()
    try:
        with urlopen(Request(endpoint, data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}), timeout=5) as response:
            active = json.load(response)
    except (HTTPError, URLError, TimeoutError, ValueError) as exc:
        raise IdentityServiceUnavailable() from exc
    if not isinstance(active, dict):
        raise IdentityServiceUnavailable()
    if active.get("active") is not True or active.get("sub") != claims["sub"]:
        raise AuthenticationFailed("登录状态无效或已过期")
    claims["is_demo"] = is_demo
    if claims['azp']=='linesight-nfc' and require_nfc_session:
        from .models import NfcSession
        try:
            binding=uuid.UUID(str(claims.get('nfc_binding')))
            allowed=NfcSession.objects.filter(sid=claims.get('sid'),credential_id=binding,
                credential__user__cloud_identity__subject=claims['sub'],credential__revoked_at__isnull=True,
                credential__user__is_active=True,revoked_at__isnull=True).exists()
        except (ValueError,TypeError):
            allowed=False
        if not allowed:raise AuthenticationFailed('卡片登录已失效，请重新登录')
    return claims


def resolve_identity(claims):
    issuer, subject = claims["iss"], claims["sub"]
    try:
        identity = CloudIdentity.objects.select_related("user", "home_workspace").get(issuer=issuer, subject=subject)
    except CloudIdentity.DoesNotExist:
        try:
            with transaction.atomic():
                # Never bind a new OIDC subject by mutable username/email. This
                # preserves legacy accounts without enabling account takeover.
                username = "oidc_" + hashlib.sha256(f"{issuer}\0{subject}".encode()).hexdigest()[:40]
                user = get_user_model().objects.create_user(username=username)
                display = str(claims.get("name") or claims.get("preferred_username") or "LineSight")[:100]
                demo = claims["is_demo"]
                workspace = Workspace.objects.create(name="演示团队" if demo else f"{display} 的工作区"[:100],
                    kind="demo" if demo else "personal")
                Membership.objects.create(workspace=workspace, user=user, role="operator" if demo else "owner")
                identity = CloudIdentity.objects.create(issuer=issuer, subject=subject, user=user,
                    display_name=display, is_demo=demo, home_workspace=workspace)
        except IntegrityError:
            identity = CloudIdentity.objects.select_related("user", "home_workspace").get(issuer=issuer, subject=subject)
    if not identity.user.is_active or identity.is_demo != claims["is_demo"]:
        raise AuthenticationFailed("登录状态无效或已过期")
    return identity
