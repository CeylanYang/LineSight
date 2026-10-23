"""Device-bound NFC proof; OAuth sessions and token lifecycle remain in Keycloak."""
import base64
import hashlib
import hmac
import json
import re
import secrets
import time
import uuid
from datetime import timedelta
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from django.conf import settings
from django.db import transaction
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import AuthenticationFailed, PermissionDenied, ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import SimpleRateThrottle
from .models import CloudIdentity, NfcCredential, NfcChallenge, NfcSession
from .oidc import IdentityServiceUnavailable, verify_access_token


class NfcThrottle(SimpleRateThrottle):
    scope='nfc'
    rate='20/minute'
    def get_cache_key(self,request,view):
        identity=f'user-{request.user.pk}' if request.user.is_authenticated else self.get_ident(request)
        return self.cache_format % {'scope':self.scope,'ident':identity}


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def card_hash(value):
    if not isinstance(value,str) or not re.fullmatch(r'[0-9a-f]{64}',value):
        raise ValidationError('无法识别此卡片，请重新扫描')
    return hmac.new(settings.SECRET_KEY.encode(),value.encode(),hashlib.sha256).hexdigest()


def recent_account(request):
    auth=request.auth if isinstance(request.auth,dict) else {}
    authenticated=auth.get('auth_time')
    if not request.user.is_authenticated or auth.get('azp') not in ('linesight-android','linesight-demo') or type(authenticated) not in (int,float) or abs(time.time()-authenticated)>300:
        raise PermissionDenied('请重新使用账户登录后绑定卡片')


def identifier(value):
    try:return uuid.UUID(str(value))
    except (ValueError,TypeError):raise AuthenticationFailed('刷卡验证已过期，请重新扫描')


def transcript(challenge):
    payload=challenge.payload
    return '\n'.join(['linesight-nfc-v1',str(challenge.id),challenge.nonce,challenge.action,
        str(challenge.credential_id or ''),payload['card_hash'],payload.get('refresh_hash','')])


def json_credential(row):
    return {'id':str(row.id),'label':row.label,'technology':row.technology,'created_at':row.created_at.isoformat(),'revoked':row.revoked_at is not None}


@api_view(['GET','DELETE'])
@permission_classes([IsAuthenticated])
def credentials(request,credential_id=None):
    if request.method=='GET':
        return Response([json_credential(row) for row in NfcCredential.objects.filter(user=request.user,revoked_at__isnull=True).order_by('-created_at')])
    with transaction.atomic():
        row=NfcCredential.objects.filter(id=credential_id,user=request.user,revoked_at__isnull=True).first()
        if row is None: raise AuthenticationFailed('卡片绑定已失效')
        row.revoked_at=timezone.now();row.save(update_fields=['revoked_at'])
        NfcSession.objects.filter(credential=row,revoked_at__isnull=True).update(revoked_at=row.revoked_at)
    return Response({'revoked':True})


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([NfcThrottle])
def challenge(request):
    action=request.data.get('action')
    if action not in ('bind','login','refresh','logout'):raise ValidationError('请选择登录或卡片管理')
    credential=None
    if action=='bind':
        recent_account(request)
        user=request.user
        try:
            key=request.data['public_key']
            if not isinstance(key,str) or len(key)!=44:raise ValueError()
            Ed25519PublicKey.from_public_bytes(base64.b64decode(key,validate=True))
        except (ValueError,TypeError,KeyError):raise ValidationError('无法读取设备密钥')
        payload={'public_key':key,'card_hash':card_hash(request.data.get('card_code')),
            'technology':str(request.data.get('technology',''))[:160], 'label':str(request.data.get('label','NFC'))[:80] or 'NFC'}
    else:
        try: credential=NfcCredential.objects.select_related('user').get(id=identifier(request.data.get('credential_id')),revoked_at__isnull=True,user__is_active=True)
        except (NfcCredential.DoesNotExist,ValueError,TypeError):raise AuthenticationFailed('请先登录并绑定此卡片')
        user=credential.user
        payload={'public_key':credential.public_key,'card_hash':credential.card_hash}
        if action=='login':
            if not hmac.compare_digest(card_hash(request.data.get('card_code')),credential.card_hash):raise AuthenticationFailed('请先登录并绑定此卡片')
        else:
            token=request.data.get('refresh_token')
            if not isinstance(token,str) or len(token)>16384:raise AuthenticationFailed('登录已过期，请重新登录')
            payload['refresh_hash']=digest(token)
            if not NfcSession.objects.filter(credential=credential,refresh_hash=payload['refresh_hash'],revoked_at__isnull=True).exists():
                raise AuthenticationFailed('登录已过期，请重新登录')
    NfcChallenge.objects.filter(expires_at__lt=timezone.now()-timedelta(days=1)).delete()
    row=NfcChallenge.objects.create(user=user,credential=credential,action=action,nonce=secrets.token_urlsafe(32),payload=payload,expires_at=timezone.now()+timedelta(seconds=60))
    return Response({'id':str(row.id),'message':transcript(row),'expires_in':60},headers={'Cache-Control':'no-store'})


def provider_form(path,fields):
    secret=getattr(settings,'LINESIGHT_NFC_CLIENT_SECRET','')
    if not secret:raise IdentityServiceUnavailable()
    fields={**fields,'client_id':'linesight-nfc','client_secret':secret}
    endpoint=settings.LINESIGHT_OIDC_ISSUER.rstrip('/')+'/protocol/openid-connect/'+path
    try:
        with urlopen(Request(endpoint,data=urlencode(fields).encode(),headers={'Content-Type':'application/x-www-form-urlencoded'}),timeout=10) as response:
            return json.load(response) if response.status!=204 else {}
    except HTTPError as exc:
        if exc.code in (400,401):raise AuthenticationFailed('登录已过期，请重新登录') from exc
        raise IdentityServiceUnavailable() from exc
    except (URLError,TimeoutError,ValueError):raise IdentityServiceUnavailable()


def login_ticket(credential):
    secret=getattr(settings,'LINESIGHT_NFC_TICKET_SECRET','')
    if len(secret)<43:raise IdentityServiceUnavailable()
    identity=CloudIdentity.objects.get(user=credential.user,issuer=settings.LINESIGHT_OIDC_ISSUER)
    now=int(time.time())
    payload=base64.urlsafe_b64encode(f'{identity.subject}|{credential.id}|{now}|{now+30}|{uuid.uuid4().hex}'.encode()).decode().rstrip('=')
    signature=base64.urlsafe_b64encode(hmac.new(secret.encode(),payload.encode(),hashlib.sha256).digest()).decode().rstrip('=')
    return payload+'.'+signature


def remember_tokens(credential,tokens,previous=None):
    claims=verify_access_token(tokens['access_token'],require_nfc_session=False)
    identity=credential.user.cloud_identity
    if claims['sub']!=identity.subject or claims.get('nfc_binding')!=str(credential.id) or not claims.get('sid'):
        raise AuthenticationFailed('卡片认证未完成，请重新登录')
    with transaction.atomic():
        locked=NfcCredential.objects.select_for_update().get(pk=credential.pk)
        if locked.revoked_at is not None:raise AuthenticationFailed('卡片绑定已失效')
        if previous is not None:
            session=NfcSession.objects.select_for_update().get(credential=locked,refresh_hash=previous,revoked_at__isnull=True)
            if claims['sid']!=session.sid:raise AuthenticationFailed('登录已过期，请重新登录')
            session.refresh_hash=digest(tokens['refresh_token']);session.save(update_fields=['refresh_hash'])
        else:
            NfcSession.objects.create(credential=locked,sid=claims['sid'],refresh_hash=digest(tokens['refresh_token']))
    return {key:tokens[key] for key in ['access_token','refresh_token','expires_in','id_token'] if key in tokens}


@api_view(['POST'])
@permission_classes([AllowAny])
@throttle_classes([NfcThrottle])
def complete(request):
    try: row=NfcChallenge.objects.select_related('credential','user').get(id=identifier(request.data.get('challenge_id')))
    except (NfcChallenge.DoesNotExist,ValueError,TypeError):raise AuthenticationFailed('刷卡验证已过期，请重新扫描')
    now=timezone.now()
    if row.consumed_at is not None or row.expires_at<=now or not row.user.is_active:raise AuthenticationFailed('刷卡验证已过期，请重新扫描')
    try:
        public=Ed25519PublicKey.from_public_bytes(base64.b64decode(row.payload['public_key'],validate=True))
        signature=request.data['signature']
        if not isinstance(signature,str) or len(signature)!=88:raise ValueError()
        public.verify(base64.b64decode(signature,validate=True),transcript(row).encode())
    except (InvalidSignature,ValueError,TypeError,KeyError):raise AuthenticationFailed('刷卡验证未通过，请重试')
    if row.action=='bind':
        recent_account(request)
        if row.user_id!=request.user.pk:raise PermissionDenied('请重新使用账户登录后绑定卡片')
    if not NfcChallenge.objects.filter(id=row.id,consumed_at__isnull=True,expires_at__gt=now).update(consumed_at=now):
        raise AuthenticationFailed('刷卡验证已过期，请重新扫描')
    if row.action=='bind':
        with transaction.atomic():
            credential,created=NfcCredential.objects.get_or_create(card_hash=row.payload['card_hash'],public_key=row.payload['public_key'],defaults={'user':row.user,'label':row.payload['label'],'technology':row.payload['technology']})
            if credential.user_id!=row.user_id:raise PermissionDenied('此卡片已在本机绑定其他账户')
            if credential.revoked_at is not None:
                credential.revoked_at=None;credential.label=row.payload['label'];credential.save(update_fields=['revoked_at','label'])
        return Response(json_credential(credential),status=201)
    credential=row.credential
    if credential.revoked_at is not None:raise AuthenticationFailed('卡片绑定已失效')
    if row.action=='login':
        tokens=provider_form('token',{'grant_type':'password','nfc_ticket':login_ticket(credential),'scope':'openid profile email'})
        return Response(remember_tokens(credential,tokens),headers={'Cache-Control':'no-store'})
    token=request.data.get('refresh_token','')
    if not isinstance(token,str) or not hmac.compare_digest(digest(token),row.payload['refresh_hash']):raise AuthenticationFailed('登录已过期，请重新登录')
    if row.action=='logout':
        provider_form('logout',{'refresh_token':token})
        NfcSession.objects.filter(credential=credential,refresh_hash=row.payload['refresh_hash']).update(revoked_at=now)
        return Response({'signed_out':True})
    # Rotation is serialized per session; a duplicate refresh cannot reuse a consumed hash.
    with transaction.atomic():
        session=NfcSession.objects.select_for_update().filter(credential=credential,refresh_hash=row.payload['refresh_hash'],revoked_at__isnull=True).first()
        if session is None:raise AuthenticationFailed('登录已过期，请重新登录')
        tokens=provider_form('token',{'grant_type':'refresh_token','refresh_token':token})
        return Response(remember_tokens(credential,tokens,previous=row.payload['refresh_hash']),headers={'Cache-Control':'no-store'})
