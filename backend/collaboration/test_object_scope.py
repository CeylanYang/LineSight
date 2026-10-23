"""Bearer-authenticated object substitution matrix for SEC-06.

Own workspace/job and a foreign object are varied independently, including
same-workspace wrong-job photos, write references, and export query parameters.
"""
import io
import tempfile
from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from PIL import Image
from rest_framework.test import APIClient
from .models import (AuditEvent, CheckTemplate, Evidence, ExceptionCase,
                     JobMutation, Membership, NotificationReceipt,
                     ProductionJob, QualityInspection, Workspace)
from .vision import ALGORITHM


class ObjectScopeTests(TestCase):
    def setUp(self):
        media = tempfile.TemporaryDirectory()
        self.addCleanup(media.cleanup)
        settings = override_settings(MEDIA_ROOT=media.name)
        settings.enable(); self.addCleanup(settings.disable)
        users = get_user_model()
        self.owner = users.objects.create_user(username='scope-owner', password='scope-password-123')
        self.stranger = users.objects.create_user(username='foreign-owner', password='scope-password-123')
        self.ws = Workspace.objects.create(name='Own scope')
        self.foreign = Workspace.objects.create(name='FOREIGN-PRIVATE-TEAM')
        Membership.objects.create(workspace=self.ws, user=self.owner, role='owner')
        Membership.objects.create(workspace=self.foreign, user=self.stranger, role='owner')
        self.jobs = [ProductionJob.objects.create(workspace=ws, part_name=name, printer='A1', quantity=1, status='inspection')
            for ws, name in [(self.ws, 'OWN-A'), (self.ws, 'OWN-B'), (self.foreign, 'FOREIGN-PRIVATE-PART')]]
        self.check = QualityInspection.objects.create(job=self.jobs[2], inspector=self.stranger, verdict='fail',
            note='FOREIGN-PRIVATE-NOTE', inspected_qty=1, pass_qty=0, fail_qty=1, scrap_qty=0)
        self.issue = ExceptionCase.objects.create(job=self.jobs[2], inspection=self.check, note='FOREIGN-PRIVATE-ISSUE')
        self.template = CheckTemplate.objects.create(workspace=self.foreign, name='FOREIGN-PRIVATE-TEMPLATE', items=[])
        buffer = io.BytesIO(); Image.new('RGB', (24,24), '#3678ea').save(buffer, format='PNG')
        self.image = buffer.getvalue()
        self.photos = []
        for job in self.jobs:
            photo = Evidence(job=job, preview_algorithm=ALGORITHM)
            photo.image.save('original.png', ContentFile(self.image), save=False)
            photo.edge_preview.save('preview.png', ContentFile(self.image), save=False)
            photo.save(); self.photos.append(photo)
        # Isolate this fixture's login throttle bucket from other test classes.
        self.client = APIClient(REMOTE_ADDR='198.51.100.42')
        login = self.client.post('/api/v1/auth/login/', {'username': self.owner.username, 'password':'scope-password-123'}, format='json')
        self.assertEqual(login.status_code, 200)
        self.client.credentials(HTTP_AUTHORIZATION='Bearer '+login.data['access'])
        self.base = f'/api/v1/workspaces/{self.ws.pk}/'
        self.path = self.base+f'jobs/{self.jobs[0].pk}/'

    def snapshot(self):
        return (list(ProductionJob.objects.order_by('pk').values()),
            list(QualityInspection.objects.order_by('pk').values()),
            list(ExceptionCase.objects.order_by('pk').values()),
            list(Evidence.objects.order_by('pk').values()),
            JobMutation.objects.count(), AuditEvent.objects.count(), NotificationReceipt.objects.count())

    def test_foreign_workspace_read_and_export_matrix(self):
        before = self.snapshot()
        base = f'/api/v1/workspaces/{self.foreign.pk}/'
        for suffix in ['jobs/','records/','metrics/','report/','report/?download=csv','templates/',
            'notifications/','members/','legacy-inspections/','printer-profiles/',
            f'jobs/{self.jobs[2].pk}/', f'jobs/{self.jobs[2].pk}/history/']:
            with self.subTest(suffix=suffix):
                response = self.client.get(base+suffix)
                self.assertEqual(response.status_code, 404)
                self.assertNotIn(b'FOREIGN-PRIVATE', response.content)
        self.assertEqual(self.snapshot(), before)

    def test_photo_workspace_job_and_object_are_all_required(self):
        for job in self.jobs:
            for photo in self.photos:
                for kind in ['original','preview']:
                    response = self.client.get(self.base+f'jobs/{job.pk}/evidence/{photo.pk}/{kind}/')
                    allowed = job.workspace_id == self.ws.pk and photo.job_id == job.pk
                    with self.subTest(job=job.pk, photo=photo.pk, kind=kind):
                        self.assertEqual(response.status_code, 200 if allowed else 404)
                        if allowed:
                            self.assertEqual(b''.join(response.streaming_content), self.image)
                            response.close()
        anonymous = APIClient()
        self.assertEqual(anonymous.get(self.path+f'evidence/{self.photos[0].pk}/original/').status_code,401)

    def test_foreign_task_exception_notification_mutations_are_rejected(self):
        before = self.snapshot()
        target = self.base+f'jobs/{self.jobs[2].pk}/'
        for method, path, body in [
            ('patch',target,{'status':'printing','version':1}),
            ('post',target+'inspection/',{'verdict':'pass','version':1}),
            ('post',target+'exceptions/',{'note':'overwrite','version':1}),
            ('post',self.base+f'exceptions/{self.issue.pk}/resolve/',{'resolution':'overwrite','version':1}),
            ('post',self.base+f'notifications/{self.jobs[2].pk}/read/',{}),
        ]:
            with self.subTest(path=path):
                self.assertEqual(getattr(self.client,method)(path,body,format='json').status_code,404)
        self.assertEqual(self.snapshot(),before)

    def test_foreign_and_same_workspace_other_job_evidence_cannot_bind_to_inspection(self):
        before = self.snapshot()
        for photo in self.photos[1:]:
            response=self.client.post(self.path+'inspection/',{'verdict':'pass','version':1,'evidence_ids':[photo.pk]},format='json',HTTP_IDEMPOTENCY_KEY='scope-attempt-'+str(photo.pk))
            self.assertEqual(response.status_code,400)
        self.assertEqual(self.snapshot(),before)

    def test_foreign_issue_template_and_assignee_cannot_be_used_as_write_references(self):
        before = self.snapshot()
        response=self.client.post(self.path+'evidence/',{'stage':'before','issue_id':self.issue.pk,
            'image':SimpleUploadedFile('reference.png',self.image,content_type='image/png')},format='multipart')
        self.assertEqual(response.status_code,400)
        response=self.client.post(self.path+'inspection/',{'version':1,'verdict':'pass','template_id':self.template.pk},format='json')
        self.assertEqual(response.status_code,400)
        for field,value in [('template_id',self.template.pk),('assignee_id',self.stranger.pk)]:
            response=self.client.post(self.base+'jobs/',{'part_name':'New','quantity':1,'printer':'A1',field:value},format='json')
            self.assertEqual(response.status_code,400)
        self.assertEqual(self.snapshot(),before)

    def test_foreign_inspection_and_export_parameters_never_expand_workspace_scope(self):
        params={'workspace_id':self.foreign.pk,'job_id':str(self.jobs[2].pk),'inspection_id':self.check.pk,
            'inspector':self.stranger.pk,'assignee':self.stranger.pk}
        for suffix, csv in [('records/',False),('jobs/',False),('metrics/',False),('report/',False),('report/',True)]:
            filters = {**params, **({'download':'csv'} if csv else {})}
            response=self.client.get(self.base+suffix,filters)
            self.assertEqual(response.status_code,200)
            self.assertNotIn(b'FOREIGN-PRIVATE',response.content)
            if filters.get('download') == 'csv':
                self.assertTrue(response['Content-Type'].startswith('text/csv'))
        self.assertEqual(self.client.get(self.base+'records/',params).data,[])
        response=self.client.get(self.base+'report/',params)
        self.assertEqual(response.data['metrics']['task_ids'],[])
        # A caller-supplied inspection ID is never a target to update.
        old=list(QualityInspection.objects.filter(pk=self.check.pk).values())
        response=self.client.post(self.path+'inspection/',{'version':1,'verdict':'pass','inspection_id':self.check.pk},format='json')
        self.assertEqual(response.status_code,201)
        self.assertEqual(list(QualityInspection.objects.filter(pk=self.check.pk).values()),old)
        self.assertEqual(QualityInspection.objects.get(job=self.jobs[0]).inspector_id,self.owner.pk)

    def test_removed_member_old_bearer_loses_objects_photos_and_exports(self):
        Membership.objects.create(workspace=self.ws,user=self.stranger,role='owner')
        admin=APIClient(REMOTE_ADDR='198.51.100.43')
        login=admin.post('/api/v1/auth/login/',{'username':self.stranger.username,'password':'scope-password-123'},format='json')
        admin.credentials(HTTP_AUTHORIZATION='Bearer '+login.data['access'])
        self.assertEqual(admin.delete(self.base+'members/'+self.owner.username+'/').status_code,200)
        for suffix in ['jobs/','records/','metrics/','report/','report/?download=csv',
            f'jobs/{self.jobs[0].pk}/', f'jobs/{self.jobs[0].pk}/history/',
            f'jobs/{self.jobs[0].pk}/evidence/{self.photos[0].pk}/original/',
            f'jobs/{self.jobs[0].pk}/evidence/{self.photos[0].pk}/preview/']:
            with self.subTest(suffix=suffix):
                self.assertEqual(self.client.get(self.base+suffix).status_code,404)
