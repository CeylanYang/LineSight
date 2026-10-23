import base64
import time
from datetime import timedelta
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.utils import timezone
from rest_framework.test import APIClient
from .models import CloudIdentity, NfcCredential, NfcChallenge, NfcSession
from .nfc import card_hash, digest

@override_settings(LINESIGHT_OIDC_ISSUER='https://identity.test/realms/linesight',LINESIGHT_NFC_TICKET_SECRET='x'*64)
class NfcTests(TestCase):
    def setUp(self):
        from django.core.cache import cache
        cache.clear()
        self.user=get_user_model().objects.create_user(username='card-user')
        CloudIdentity.objects.create(user=self.user,issuer='https://identity.test/realms/linesight',subject='subject-one')
        self.client=APIClient();self.authorize()
        self.private=Ed25519PrivateKey.generate()
        self.public=base64.b64encode(self.private.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)).decode()
        self.card='a'*64;self.base='/api/v1/auth/nfc/'
    def authorize(self,client=None,user=None):
        (client or self.client).force_authenticate(user or self.user,token={'azp':'linesight-android','auth_time':int(time.time())})
    def start(self,action='bind',**fields):
        payload={'action':action,**fields}
        if action=='bind':payload.update(public_key=self.public,card_code=self.card)
        return self.client.post(self.base+'challenges/',payload,format='json')
    def prove(self,challenge,private=None,**fields):
        data=challenge.data
        return self.client.post(self.base+'complete/',{'challenge_id':data['id'],'signature':base64.b64encode((private or self.private).sign(data['message'].encode())).decode(),**fields},format='json')
    def bind(self):
        response=self.prove(self.start());self.assertEqual(response.status_code,201,response.data)
        return NfcCredential.objects.get(pk=response.data['id'])
    def tokens(self,credential,refresh='refresh-new',sid='session-one'):
        result={'access_token':'access-one','refresh_token':refresh,'expires_in':300}
        claims={'sub':'subject-one','nfc_binding':str(credential.pk),'sid':sid}
        return patch('collaboration.nfc.provider_form',return_value=result),patch('collaboration.nfc.verify_access_token',return_value=claims)
    def test_binding_requires_recent_account_and_possession_of_device_key(self):
        challenge=self.start()
        self.assertEqual(self.prove(challenge,Ed25519PrivateKey.generate()).status_code,401)
        self.assertEqual(NfcCredential.objects.count(),0)
        good=self.prove(challenge);self.assertEqual(good.status_code,201)
        self.assertEqual(self.prove(challenge).status_code,401)
        self.client.force_authenticate(self.user,token={'azp':'linesight-nfc','auth_time':int(time.time())})
        self.assertEqual(self.start().status_code,403)
        self.client.force_authenticate(self.user,token={'azp':'linesight-android','auth_time':int(time.time())-301})
        self.assertEqual(self.start().status_code,403)
        self.client.force_authenticate(user=None)
        self.assertEqual(self.start().status_code,403)
    def test_login_requires_card_device_proof_and_one_use_challenge(self):
        row=self.bind();self.client.force_authenticate(user=None)
        self.assertEqual(self.start('login',credential_id=str(row.id),card_code='b'*64).status_code,401)
        challenge=self.start('login',credential_id=str(row.id),card_code=self.card)
        self.assertEqual(self.prove(challenge,Ed25519PrivateKey.generate()).status_code,401)
        provider,verify=self.tokens(row)
        with provider as exchange,verify:
            response=self.prove(challenge);self.assertEqual(response.status_code,200,response.data)
            ticket=exchange.call_args.args[1]['nfc_ticket'];self.assertEqual(len(ticket.split('.')),2)
            self.assertEqual(self.prove(challenge).status_code,401)
            self.assertEqual(exchange.call_count,1)
        self.assertEqual(NfcSession.objects.get().refresh_hash,digest('refresh-new'))
    def test_expired_or_tampered_challenge_cannot_create_session(self):
        row=self.bind();challenge=self.start('login',credential_id=str(row.id),card_code=self.card)
        NfcChallenge.objects.filter(id=challenge.data['id']).update(expires_at=timezone.now()-timedelta(seconds=1))
        with patch('collaboration.nfc.provider_form') as provider:
            self.assertEqual(self.prove(challenge).status_code,401);provider.assert_not_called()
        self.assertEqual(NfcSession.objects.count(),0)
    def test_refresh_rotates_bound_session_and_logout_revokes_it(self):
        row=self.bind();NfcSession.objects.create(credential=row,sid='session-one',refresh_hash=digest('old-token'))
        self.client.force_authenticate(user=None)
        challenge=self.start('refresh',credential_id=str(row.id),refresh_token='old-token')
        self.assertEqual(self.prove(challenge,refresh_token='wrong-token').status_code,401)
        challenge=self.start('refresh',credential_id=str(row.id),refresh_token='old-token')
        provider,verify=self.tokens(row)
        with provider,verify:
            response=self.prove(challenge,refresh_token='old-token');self.assertEqual(response.status_code,200,response.data)
        self.assertEqual(self.start('refresh',credential_id=str(row.id),refresh_token='old-token').status_code,401)
        challenge=self.start('logout',credential_id=str(row.id),refresh_token='refresh-new')
        with patch('collaboration.nfc.provider_form',return_value={}):
            self.assertEqual(self.prove(challenge,refresh_token='refresh-new').status_code,200)
        self.assertIsNotNone(NfcSession.objects.get().revoked_at)
    def test_revoke_is_owner_scoped_and_blocks_card_and_refresh(self):
        row=self.bind();NfcSession.objects.create(credential=row,sid='session-one',refresh_hash=digest('old-token'))
        foreign=APIClient();self.authorize(foreign,get_user_model().objects.create_user(username='other-card-user'))
        self.assertEqual(foreign.delete(self.base+f'credentials/{row.id}/').status_code,401)
        self.assertEqual(self.client.delete(self.base+f'credentials/{row.id}/').status_code,200)
        self.assertIsNotNone(NfcSession.objects.get().revoked_at)
        self.assertEqual(self.start('login',credential_id=str(row.id),card_code=self.card).status_code,401)
        self.assertEqual(self.start('refresh',credential_id=str(row.id),refresh_token='old-token').status_code,401)
    def test_one_device_card_cannot_be_rebound_to_another_account(self):
        self.bind();other=get_user_model().objects.create_user(username='other-card-user');self.authorize(user=other)
        self.assertEqual(self.prove(self.start()).status_code,403)
        self.assertEqual(NfcCredential.objects.get().user_id,self.user.id)
    def test_malformed_inputs_are_rejected_and_raw_card_is_not_stored(self):
        row=self.bind();self.assertEqual(row.card_hash,card_hash(self.card));self.assertNotEqual(row.card_hash,self.card)
        for value in ['bad',None,'../user']:
            self.assertEqual(self.start('login',credential_id=value,card_code=self.card).status_code,401)
            self.assertEqual(self.client.post(self.base+'complete/',{'challenge_id':value,'signature':'bad'},format='json').status_code,401)
    def test_provider_subject_and_binding_must_match_before_token_delivery(self):
        row=self.bind();challenge=self.start('login',credential_id=str(row.id),card_code=self.card)
        with patch('collaboration.nfc.provider_form',return_value={'access_token':'access','refresh_token':'refresh','expires_in':300}),patch('collaboration.nfc.verify_access_token',return_value={'sub':'wrong','nfc_binding':str(row.id),'sid':'s1'}):
            self.assertEqual(self.prove(challenge).status_code,401)
        self.assertEqual(NfcSession.objects.count(),0)
