from django.contrib.auth import get_user_model
from django.test import TestCase
from django.core.cache import cache
from rest_framework.test import APIClient
from .models import AuditEvent, CheckTemplate, Membership, PrinterProfile, Workspace

class ProfileManagementTests(TestCase):
    def tearDown(self):
        cache.clear()

    def setUp(self):
        cache.clear()
        self.user = get_user_model().objects.create_user(username='profile-owner')
        self.workspace = Workspace.objects.create(name='Profiles')
        self.member = Membership.objects.create(workspace=self.workspace,user=self.user,role='owner')
        self.client = APIClient()
        self.client.force_authenticate(self.user,token={'iss':'https://trusted.example','iat':100})
        self.url = f'/api/v1/workspaces/{self.workspace.pk}/printer-profiles/'
        self.jobs = f'/api/v1/workspaces/{self.workspace.pk}/jobs/'
        self.template = CheckTemplate.objects.create(workspace=self.workspace,name='Checklist',items=[{'id':str(i),'label':str(i),'required':True,'allow_na':False} for i in range(3)])
        self.body = {'name':'Station printer','version':'v1','source':'https://example.com/profile','note':'PLA','default_template_id':self.template.pk}
    def save(self, body=None, key='profile-request-0001'):
        return self.client.post(self.url, self.body if body is None else body,format='json',HTTP_IDEMPOTENCY_KEY=key)
    def job(self, body, key='profile-job-request-0001'):
        return self.client.post(self.jobs,body,format='json',HTTP_IDEMPOTENCY_KEY=key)
    def test_save_and_replay_after_later_update_preserve_original_receipt(self):
        first = self.save(); self.assertEqual(first.status_code,201)
        edit = {**self.body,'id':first.data['id'],'revision':1,'version':'v2','default_template_id':None}
        newer = self.save(edit,'profile-request-0002')
        self.assertEqual(newer.data['revision'],2)
        self.assertEqual(self.save().data,first.data)
        self.assertEqual(self.save(edit,'profile-request-0002').data,newer.data)
        self.assertEqual(AuditEvent.objects.filter(action='profile.saved').count(),2)
    def test_stale_editor_cannot_overwrite_and_returns_current(self):
        first = self.save().data
        edit = {**self.body,'id':first['id'],'revision':1,'version':'v2'}
        self.assertEqual(self.save(edit,'profile-request-0002').status_code,200)
        stale = self.save({**edit,'note':'Other'},'profile-request-0003')
        self.assertEqual(stale.status_code,409)
        self.assertEqual(stale.data['current']['revision'],2)
        self.assertEqual(PrinterProfile.objects.get().note,'PLA')
    def test_copy_requires_unique_name_and_does_not_mutate_source(self):
        first = self.save().data
        self.assertEqual(self.save(key='profile-request-0002').status_code,409)
        copy = self.save({**self.body,'name':'Copied printer'},'profile-request-0003')
        self.assertEqual(copy.status_code,201)
        self.assertNotEqual(copy.data['id'],first['id'])
        self.assertEqual(copy.data['default_template_id'],self.template.pk)
        self.assertEqual(PrinterProfile.objects.count(),2)
    def test_cloud_keys_and_valid_https_are_required(self):
        self.assertEqual(self.save(key='').status_code,400)
        for source in ['https://','http://example.com','https://example.com/'+'x'*300]:
            self.assertEqual(self.save({**self.body,'source':source}).status_code,400)
        self.assertFalse(PrinterProfile.objects.exists())
    def test_changed_payload_or_actor_cannot_reuse_key(self):
        self.save()
        self.assertEqual(self.save({**self.body,'note':'Changed'}).status_code,409)
        other = get_user_model().objects.create_user(username='another-owner')
        Membership.objects.create(workspace=self.workspace,user=other,role='owner')
        self.client.force_authenticate(other,token={'iss':'https://trusted.example','iat':100})
        self.assertEqual(self.save().status_code,409)
    def test_foreign_profiles_and_templates_never_exposed(self):
        other = Workspace.objects.create(name='Other')
        foreign = PrinterProfile.objects.create(workspace=other,name='Private',version='v1',source_url='https://example.com')
        self.assertEqual(self.save({**self.body,'id':f'workspace:{foreign.pk}','revision':1}).status_code,404)
        template = CheckTemplate.objects.create(workspace=other,name='Private',items=[])
        self.assertEqual(self.save({**self.body,'default_template_id':template.pk}).status_code,400)
        self.assertEqual(self.save({**self.body,'id':'starter:a1','revision':0}).status_code,404)
    def test_revocation_checked_before_receipt_replay(self):
        self.save();self.member.role='viewer';self.member.save()
        self.assertEqual(self.save().status_code,403)
        self.member.delete();self.assertEqual(self.save().status_code,404)
    def test_default_template_applies_to_future_jobs_and_receipts_survive_edits(self):
        profile = self.save().data
        body = {'part_name':'Bracket','printer':profile['name'],'quantity':1,'profile_id':profile['id'],'profile_revision':1}
        first = self.job(body);self.assertEqual(first.status_code,201)
        self.assertEqual(first.data['template']['id'],self.template.pk)
        self.save({**self.body,'id':profile['id'],'revision':1,'version':'v2','default_template_id':None},'profile-request-0002')
        replay = self.job(body);self.assertEqual(replay.status_code,200)
        self.assertEqual(replay.data['id'],first.data['id']);self.assertEqual(replay.data['profile_version'],'v1')
        self.assertEqual(replay.data['template']['id'],self.template.pk)
        stale = self.job(body,'profile-job-request-0002');self.assertEqual(stale.status_code,409)
        self.assertEqual(stale.data['current']['revision'],2)
        second = self.job({**body,'profile_revision':2},'profile-job-request-0003')
        self.assertEqual(second.status_code,201);self.assertEqual(second.data['profile_version'],'v2');self.assertIsNone(second.data['template'])
    def test_explicit_template_overrides_bound_template_and_clear_is_explicit(self):
        profile = self.save().data
        other = CheckTemplate.objects.create(workspace=self.workspace,name='Override',items=[])
        body={'part_name':'Bracket','printer':profile['name'],'quantity':1,'profile_id':profile['id']}
        selected=self.job({**body,'template_id':other.pk})
        self.assertEqual(selected.data['template']['id'],other.pk)
        cleared=self.job({**body,'template_id':None},'profile-job-request-0002')
        self.assertIsNone(cleared.data['template'])
    def test_profile_rename_requires_copy_and_huge_id_returns_not_found(self):
        profile = self.save().data
        self.assertEqual(self.save({**self.body,'name':'Renamed','id':profile['id'],'revision':1},'profile-request-0002').status_code,400)
        self.assertEqual(self.job({'part_name':'Bad','printer':'Bad','quantity':1,'profile_id':'workspace:'+'9'*100}).status_code,404)
