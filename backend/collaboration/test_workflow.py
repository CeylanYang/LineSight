from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient
from .models import AuditEvent, ExceptionCase, JobMutation, Membership, ProductionJob, QualityInspection, Workspace


class VersionedWorkflowTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username='owner')
        self.workspace = Workspace.objects.create(name='Workflow')
        Membership.objects.create(user=self.user, workspace=self.workspace, role='owner')
        self.client = APIClient(); self.client.force_authenticate(self.user)
        self.job = ProductionJob.objects.create(workspace=self.workspace, part_name='Bracket', printer='A1', quantity=10, status='inspection')
        self.path = f'/api/v1/workspaces/{self.workspace.pk}/jobs/{self.job.pk}/'
        self.key = 'inspection-request-0001'

    def fail(self):
        response = self.client.post(self.path + 'inspection/', {'verdict': 'fail', 'note': 'Crack', 'version': 1},
                                    format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        self.assertEqual(response.status_code, 201)
        return ExceptionCase.objects.get(job=self.job)

    def test_inspection_retry_has_one_immutable_result_and_event(self):
        body = {'verdict': 'pass', 'version': 1}
        first = self.client.post(self.path + 'inspection/', body, format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        replay = self.client.post(self.path + 'inspection/', body, format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        self.assertEqual(first.status_code, 201)
        self.assertEqual(replay.data, first.data)
        self.assertEqual(QualityInspection.objects.count(), 1)
        self.assertEqual(AuditEvent.objects.filter(action='inspection.pass').count(), 1)
        self.assertEqual(JobMutation.objects.count(), 1)
        self.job.refresh_from_db(); self.assertEqual(self.job.version, 2)
        conflicting = self.client.post(self.path + 'inspection/', {'verdict': 'fail', 'note': 'different', 'version': 1},
            format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        self.assertEqual(conflicting.status_code, 409)
        self.assertEqual(conflicting.data['code'], 'idempotency_conflict')

    def test_stale_version_returns_current_without_adding_check(self):
        self.job.version = 4; self.job.save()
        result = self.client.post(self.path + 'inspection/', {'verdict': 'pass', 'version': 1}, format='json')
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.data['current']['version'], 4)
        self.assertFalse(QualityInspection.objects.exists())

    def test_invalid_request_rolls_back_version_and_receipt(self):
        result = self.client.post(self.path + 'inspection/', {'verdict': 'fail', 'version': 1}, format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        self.assertEqual(result.status_code, 400)
        self.job.refresh_from_db(); self.assertEqual(self.job.version, 1)
        self.assertFalse(JobMutation.objects.exists())
        self.assertFalse(AuditEvent.objects.exists())

    def test_exception_cannot_be_closed_or_reinspected_by_patching_status(self):
        self.fail()
        for target in ('closed', 'inspection'):
            result = self.client.patch(self.path, {'status': target, 'version': 2}, format='json')
            self.assertEqual(result.status_code, 409)
        self.job.refresh_from_db(); self.assertEqual(self.job.status, 'exception')
        self.assertEqual(self.job.version, 2)

    def test_resolution_is_append_only_and_reinspection_adds_round(self):
        case = self.fail()
        path = f'/api/v1/workspaces/{self.workspace.pk}/exceptions/{case.pk}/resolve/'
        body = {'resolution': 'Reprinted', 'version': 2}
        first = self.client.post(path, body, format='json', HTTP_IDEMPOTENCY_KEY='resolution-request-0001')
        self.assertEqual(first.status_code, 200)
        replay = self.client.post(path, body, format='json', HTTP_IDEMPOTENCY_KEY='resolution-request-0001')
        self.assertEqual(replay.data, first.data)
        changed = self.client.post(path, {'resolution': 'Overwritten', 'version': 3}, format='json')
        self.assertEqual(changed.status_code, 409)
        case.refresh_from_db(); self.assertEqual(case.resolution, 'Reprinted')
        result = self.client.post(self.path + 'inspection/', {'verdict': 'pass', 'version': 3}, format='json')
        self.assertEqual(result.status_code, 201)
        self.assertEqual(QualityInspection.objects.filter(job=self.job).count(), 2)
        self.assertEqual(list(QualityInspection.objects.order_by('pk').values_list('verdict', flat=True)), ['fail', 'pass'])
        self.assertEqual(self.client.patch(self.path, {'status': 'printing', 'version': 4}, format='json').status_code, 409)
        history = self.client.get(self.path + 'history/')
        self.assertEqual([r['version'] for r in history.data], [2, 2, 3, 4])
        self.assertEqual(history.data[2]['details']['resolution'], 'Reprinted')

    def test_authorized_close_requires_owner_disposition_and_reason(self):
        case = self.fail()
        path = f'/api/v1/workspaces/{self.workspace.pk}/exceptions/{case.pk}/resolve/'
        body = {'resolution': 'Scrapped', 'next_status': 'closed', 'version': 2}
        self.assertEqual(self.client.post(path, body, format='json').status_code, 400)
        body.update(disposition='scrapped', closure_reason='All affected pieces removed')
        Membership.objects.filter(user=self.user).update(role='operator')
        self.assertEqual(self.client.post(path, body, format='json').status_code, 403)
        self.job.refresh_from_db(); self.assertEqual(self.job.version, 2)
        Membership.objects.filter(user=self.user).update(role='owner')
        self.assertEqual(self.client.post(path, body, format='json').status_code, 200)
        event = AuditEvent.objects.get(action='exception.resolved')
        self.assertEqual(event.details['actor_role'], 'owner')
        self.assertEqual(event.details['disposition'], 'scrapped')
        self.assertEqual(self.client.post(path, body, format='json').status_code, 409)

    def test_multiple_open_issues_block_release(self):
        case = self.fail()
        second = ExceptionCase.objects.create(job=self.job, note='Another open issue')
        path = f'/api/v1/workspaces/{self.workspace.pk}/exceptions/{case.pk}/resolve/'
        body = {'resolution': 'Done', 'version': 2, 'next_status': 'closed', 'disposition': 'scrapped', 'closure_reason': 'Evidence'}
        self.assertEqual(self.client.post(path, body, format='json').status_code, 409)
        body['next_status'] = 'inspection'
        result = self.client.post(path, body, format='json')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.data['job_status'], 'exception')
        self.assertEqual(self.client.post(self.path + 'inspection/', {'verdict': 'pass', 'version': 3}, format='json').status_code, 409)
        second.refresh_from_db(); self.assertEqual(second.status, 'open')

    def test_cloud_commands_require_version_and_idempotency_key(self):
        self.client.force_authenticate(self.user, token={'iss': 'https://trusted.example', 'iat': 100})
        result = self.client.post(self.path + 'inspection/', {'verdict': 'pass'}, format='json')
        self.assertEqual(result.status_code, 400)
        self.assertEqual(result.data['code'], 'idempotency_required')
        result = self.client.post(self.path + 'inspection/', {'verdict': 'pass'}, format='json', HTTP_IDEMPOTENCY_KEY=self.key)
        self.assertEqual(result.data['code'], 'version_required')

    def test_history_is_scoped_to_workspace(self):
        self.fail()
        stranger = get_user_model().objects.create_user(username='stranger')
        self.client.force_authenticate(stranger)
        self.assertEqual(self.client.get(self.path + 'history/').status_code, 404)
