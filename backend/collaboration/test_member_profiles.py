import base64
from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.core.cache import cache
from rest_framework.test import APIClient
from .models import CloudIdentity, Membership, Workspace

class MemberProfileTests(TestCase):
    def setUp(self):
        cache.clear()
        self.workspace=Workspace.objects.create(name='checkcheck')
        self.owner=get_user_model().objects.create_user(username='seed-owner')
        self.manager=get_user_model().objects.create_user(username='seed-manager')
        self.operator=get_user_model().objects.create_user(username='seed-operator')
        for user,role in [(self.owner,'owner'),(self.manager,'manager'),(self.operator,'operator')]:
            Membership.objects.create(workspace=self.workspace,user=user,role=role)
            CloudIdentity.objects.create(user=user,issuer='https://trusted',subject=str(user.pk),home_workspace=self.workspace,display_name=user.username,avatar_seed=str(user.pk),job_title='Quality')
        self.client=APIClient()
        self.base=f'/api/v1/workspaces/{self.workspace.pk}/'
    def tearDown(self):cache.clear()
    def as_user(self,user):self.client.force_authenticate(user,token={'preferred_username':user.username})
    def test_manager_can_publish_template_and_config_but_operator_cannot(self):
        self.as_user(self.manager)
        template={'name':'Work checks','items':[{'id':str(i),'label':str(i),'required':True} for i in range(3)]}
        self.assertEqual(self.client.post(self.base+'templates/',template,format='json',HTTP_IDEMPOTENCY_KEY='manager-template-0001').status_code,201)
        profile={'name':'Production printer','version':'v1','source':'https://bambulab.com/en/a1'}
        self.assertEqual(self.client.post(self.base+'printer-profiles/',profile,format='json',HTTP_IDEMPOTENCY_KEY='manager-profile-0001').status_code,201)
        self.as_user(self.operator)
        self.assertEqual(self.client.post(self.base+'templates/',template,format='json').status_code,403)
        self.assertEqual(self.client.post(self.base+'printer-profiles/',profile,format='json').status_code,403)
    def test_manager_cannot_invite_remove_or_promote_members(self):
        self.as_user(self.manager)
        self.assertEqual(self.client.post(self.base+'invite/',{'role':'operator'},format='json').status_code,403)
        url=self.base+'members/'+self.operator.username+'/'
        self.assertEqual(self.client.patch(url,{'role':'owner'},format='json').status_code,403)
        self.assertEqual(self.client.delete(url).status_code,403)
    def test_owner_invites_manager_once_and_never_invites_owner(self):
        self.as_user(self.owner)
        self.assertEqual(self.client.post(self.base+'invite/',{'role':'owner'},format='json').status_code,400)
        result=self.client.post(self.base+'invite/',{'role':'manager'},format='json')
        self.assertEqual(result.status_code,201)
        joiner=get_user_model().objects.create_user(username='invited-manager')
        self.as_user(joiner)
        response=self.client.post('/api/v1/workspaces/redeem/',{'code':result.data['code']},format='json')
        self.assertEqual(response.status_code,201)
        self.assertEqual(response.data['role'],'manager')
        self.assertEqual(Membership.objects.get(user=joiner).role,'manager')
        for invalid in (None, {}, [], 123, '', 'short'):
            self.assertEqual(self.client.post('/api/v1/workspaces/redeem/',{'code':invalid},format='json').status_code,400)
    def test_manager_can_receive_tasks_and_operator_can_submit(self):
        self.as_user(self.operator)
        response=self.client.post(self.base+'jobs/',{'part_name':'Clamp','printer':'A1','quantity':2,'assignee_id':self.manager.pk},format='json',HTTP_IDEMPOTENCY_KEY='manager-assignee-0001')
        self.assertEqual(response.status_code,201)
        self.assertEqual(response.data['assignee_id'],self.manager.pk)
    def test_profile_portrait_matches_members_and_is_team_scoped(self):
        self.as_user(self.manager)
        me=self.client.get('/api/v1/auth/me/').data
        self.assertEqual(me['job_title'],'Quality')
        self.assertTrue(base64.b64decode(me['avatar_data']).startswith(b'\x89PNG\r\n\x1a\n'))
        members=self.client.get(self.base+'members/').data
        self.assertEqual(next(m['avatar_data'] for m in members if m['is_self']),me['avatar_data'])
        self.assertEqual(len({m['avatar_data'] for m in members}),3)
        outsider=get_user_model().objects.create_user(username='outsider')
        self.as_user(outsider)
        self.assertEqual(self.client.get(self.base+'members/').status_code,404)
    @override_settings(LINESIGHT_OIDC_ISSUER='https://trusted')
    def test_legacy_anonymous_registration_cannot_create_accounts(self):
        self.client.force_authenticate(None)
        before=get_user_model().objects.count()
        self.assertEqual(self.client.post('/api/v1/auth/register/',{'username':'outsider2','password':'SomePassword12!'},format='json').status_code,410)
        self.assertEqual(get_user_model().objects.count(),before)

    @override_settings(LINESIGHT_OIDC_ISSUER='')
    def test_registration_stays_closed_without_identity_configuration(self):
        self.client.force_authenticate(None)
        before = get_user_model().objects.count()
        for payload in [{}, {'username': 'outsider-new', 'password': 'SomePassword12!'}, {'username': 'outsider-new', 'password': 'SomePassword12!', 'code': 'pretend-invitation-token'}]:
            response = self.client.post('/api/v1/auth/register/', payload, format='json')
            self.assertEqual(response.status_code, 410)
            self.assertEqual(get_user_model().objects.count(), before)
        self.assertFalse(get_user_model().objects.filter(username='outsider-new').exists())
