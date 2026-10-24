from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient
from .models import AuditEvent, ExceptionCase, JobMutation, Membership, ProductionJob, QualityInspection, Workspace


class AssignmentTests(TestCase):
    def setUp(self):
        cache.clear()
        users = get_user_model()
        self.owner = users.objects.create_user(username='assignment-owner')
        self.first = users.objects.create_user(username='assignment-first')
        self.second = users.objects.create_user(username='assignment-second')
        self.viewer = users.objects.create_user(username='assignment-viewer')
        self.foreign = users.objects.create_user(username='assignment-foreign')
        self.workspace = Workspace.objects.create(name='Assignment')
        self.other = Workspace.objects.create(name='Other assignment')
        for user, role in [(self.owner, 'owner'), (self.first, 'operator'), (self.second, 'operator'), (self.viewer, 'viewer')]:
            Membership.objects.create(workspace=self.workspace, user=user, role=role)
        Membership.objects.create(workspace=self.other, user=self.foreign, role='owner')
        self.job = ProductionJob.objects.create(workspace=self.workspace, part_name='Bracket', printer='A1', quantity=3, status='inspection', assignee=self.first)
        self.base = f'/api/v1/workspaces/{self.workspace.pk}/'
        self.path = self.base + f'jobs/{self.job.pk}/assignment/'
        self.client = APIClient()
        self.client.force_authenticate(self.owner, token={'iss': 'https://identity.example'})

    def tearDown(self):
        cache.clear()

    def assign(self, selected, version=1, key='assignment-request-0001', note=''):
        return self.client.post(self.path, {'assignee_id': selected, 'version': version, 'note': note}, format='json', HTTP_IDEMPOTENCY_KEY=key)

    def notices(self, user):
        client = APIClient(); client.force_authenticate(user)
        return client.get(self.base + 'notifications/').data

    def test_assignment_changes_recipient_and_audits_identity_and_version(self):
        self.assertEqual(len(self.notices(self.first)), 1)
        result = self.assign(self.second.pk)
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.data['assignee_id'], self.second.pk)
        self.assertEqual(result.data['version'], 2)
        self.assertEqual(self.notices(self.first), [])
        self.assertEqual(self.notices(self.second)[0]['version'], 2)
        self.assertFalse(self.notices(self.second)[0]['read'])
        event = AuditEvent.objects.get(action='job.assigned')
        self.assertEqual(event.user, self.owner)
        self.assertEqual(event.details['previous_assignee_id'], self.first.pk)
        self.assertEqual(event.details['assignee_id'], self.second.pk)
        self.assertEqual(event.version, 2)

    def test_exception_handoff_requires_note_and_preserves_resolved_history(self):
        self.job.status = 'exception'; self.job.save()
        check = QualityInspection.objects.create(job=self.job, inspector=self.first, verdict='fail', note='Crack')
        pending = ExceptionCase.objects.create(job=self.job, inspection=check, note='Crack', assignee='First')
        resolved = ExceptionCase.objects.create(job=self.job, status='resolved', note='Old', assignee='Original', resolution='Fixed')
        self.assertEqual(self.assign(self.second.pk).status_code, 400)
        result = self.assign(self.second.pk, note='Continue the crack repair')
        self.assertEqual(result.status_code, 200)
        pending.refresh_from_db(); resolved.refresh_from_db(); check.refresh_from_db()
        self.assertEqual(pending.assignee, self.second.username)
        self.assertEqual((resolved.assignee, resolved.resolution), ('Original', 'Fixed'))
        self.assertEqual((check.inspector_id, check.verdict), (self.first.pk, 'fail'))
        event = AuditEvent.objects.get(action='job.assigned')
        self.assertEqual(event.details['handed_over_issues'], [{'id': pending.pk, 'assignee': 'First'}])
        self.assertEqual(event.details['note'], 'Continue the crack repair')

    def test_unassignment_returns_inspection_to_shared_queue(self):
        result = self.assign(None)
        self.assertEqual(result.status_code, 200)
        self.assertIsNone(result.data['assignee_id'])
        self.assertEqual(len(self.notices(self.first)), 1)
        self.assertEqual(len(self.notices(self.second)), 1)

    def test_receipt_replay_survives_later_assignment_and_conflicting_body_or_actor_is_rejected(self):
        first = self.assign(self.second.pk)
        self.assertEqual(self.assign(self.owner.pk, version=2, key='assignment-request-0002').status_code, 200)
        replay = self.assign(self.second.pk)
        self.assertEqual(replay.data, first.data)
        self.assertEqual(self.assign(None).status_code, 409)
        self.client.force_authenticate(self.first, token={'iss': 'https://identity.example'})
        self.assertEqual(self.assign(self.second.pk).status_code, 409)
        self.assertEqual(JobMutation.objects.count(), 2)
        self.job.refresh_from_db(); self.assertEqual(self.job.assignee_id, self.owner.pk)

    def test_stale_version_conflict_does_not_change_assignment_or_issues(self):
        self.job.version = 3; self.job.save()
        result = self.assign(self.second.pk)
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.data['current']['assignee_id'], self.first.pk)
        self.assertFalse(AuditEvent.objects.exists())
        self.assertFalse(JobMutation.objects.exists())

    def test_invalid_ineligible_and_unchanged_members_roll_back_version(self):
        for selected in [True, 'invalid', 0, 2**64, self.viewer.pk, self.foreign.pk, self.first.pk]:
            with self.subTest(selected=selected):
                self.assertEqual(self.assign(selected).status_code, 400)
        self.second.is_active = False; self.second.save()
        self.assertEqual(self.assign(self.second.pk).status_code, 400)
        self.job.refresh_from_db(); self.assertEqual(self.job.version, 1)
        self.assertFalse(JobMutation.objects.exists())
        self.assertFalse(AuditEvent.objects.exists())

    def test_closed_job_missing_version_key_and_assignee_are_rejected(self):
        self.job.status = 'closed'; self.job.save()
        self.assertEqual(self.assign(self.second.pk).status_code, 409)
        self.assertEqual(self.client.post(self.path, {'assignee_id': self.second.pk}, format='json').status_code, 400)
        self.job.status = 'inspection'; self.job.save()
        self.assertEqual(self.client.post(self.path, {'version': 1}, format='json', HTTP_IDEMPOTENCY_KEY='assignment-request-0001').status_code, 400)
        self.job.refresh_from_db(); self.assertEqual(self.job.version, 1)

    def test_viewer_removed_member_foreign_workspace_and_anonymous_cannot_assign(self):
        self.client.force_authenticate(self.viewer)
        self.assertEqual(self.assign(self.second.pk).status_code, 403)
        Membership.objects.filter(workspace=self.workspace, user=self.viewer).delete()
        self.assertEqual(self.assign(self.second.pk).status_code, 404)
        self.client.force_authenticate(self.foreign)
        self.assertEqual(self.assign(self.second.pk).status_code, 404)
        self.client.force_authenticate(None)
        self.assertEqual(self.assign(self.second.pk).status_code, 401)

    def test_create_task_rejects_malformed_or_read_only_recipient(self):
        for selected in ['not-an-id', True, 2**64, self.viewer.pk, self.foreign.pk]:
            result = self.client.post(self.base+'jobs/', {'part_name': 'New', 'printer': 'A1', 'quantity': 1, 'assignee_id': selected}, format='json', HTTP_IDEMPOTENCY_KEY='assignment-create-0001')
            self.assertEqual(result.status_code, 400)
        self.assertEqual(ProductionJob.objects.count(), 1)
