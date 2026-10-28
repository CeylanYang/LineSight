"""Reject malformed inspection data without changing the task or its receipts."""
from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient
from .models import AuditEvent, CheckTemplate, JobMutation, Membership, ProductionJob, QualityInspection, Workspace


class InspectionPayloadTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username='inspector')
        self.workspace = Workspace.objects.create(name='Payload checks')
        Membership.objects.create(user=self.user, workspace=self.workspace, role='owner')
        self.client = APIClient()
        self.client.force_authenticate(self.user)
        self.job = ProductionJob.objects.create(workspace=self.workspace, part_name='Bracket', quantity=1, status='inspection')
        self.path = f'/api/v1/workspaces/{self.workspace.pk}/jobs/{self.job.pk}/inspection/'
        self.key = 'payload-validation-0001'

    def submit(self, **fields):
        return self.client.post(self.path, {'version': 1, 'verdict': 'pass', **fields}, format='json', HTTP_IDEMPOTENCY_KEY=self.key)

    def assert_rejected(self, response):
        self.assertEqual(response.status_code, 400, response.data)
        self.job.refresh_from_db()
        self.assertEqual((self.job.status, self.job.version), ('inspection', 1))
        self.assertFalse(QualityInspection.objects.exists())
        self.assertFalse(AuditEvent.objects.exists())
        self.assertFalse(JobMutation.objects.exists())

    def test_template_id_requires_positive_database_integer(self):
        for value in ['abc', '1', [], {}, True, False, 0, -1, 1.5, 2**63]:
            with self.subTest(value=value):
                self.assert_rejected(self.submit(template_id=value))
        # Correcting the form can reuse its unconsumed request key.
        self.assertEqual(self.submit().status_code, 201)
        self.assertEqual(QualityInspection.objects.count(), 1)
        self.assertEqual(JobMutation.objects.count(), 1)

    def test_answers_need_a_template_even_without_required_items(self):
        for value in [None, {}, 'pass', [1], [{'id': 'invented', 'result': 'pass'}]]:
            with self.subTest(value=value):
                self.assert_rejected(self.submit(answers=value))
        self.assertEqual(self.submit(answers=[]).status_code, 201)
        self.assertEqual(QualityInspection.objects.get().answers, [])

    def test_answer_notes_are_bounded_text_and_preserve_template_snapshot(self):
        template = CheckTemplate.objects.create(workspace=self.workspace, name='Surface', items=[{'id': 'surface', 'label': 'Surface', 'required': True, 'allow_na': False}])
        self.job.template = template
        self.job.save(update_fields=['template'])
        for value in [None, {}, [], 42, 'x' * 501]:
            with self.subTest(value=value):
                self.assert_rejected(self.submit(answers=[{'id': 'surface', 'result': 'pass', 'note': value}]))
        self.assertEqual(self.submit(answers=[{'id': 'surface', 'result': 'pass', 'note': 'x' * 500}]).status_code, 201)
        check = QualityInspection.objects.get()
        self.assertEqual(check.template_snapshot['id'], template.pk)
        self.assertEqual(len(check.answers[0]['note']), 500)
        template.items = []
        template.save(update_fields=['items'])
        check.refresh_from_db()
        self.assertEqual(len(check.template_snapshot['items']), 1)
