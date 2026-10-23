from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.test import APIClient
from .models import AuditEvent, CheckTemplate, Membership, Workspace


class TemplatePublicationTests(TestCase):
    def setUp(self):
        self.user = get_user_model().objects.create_user(username='template-owner')
        self.workspace = Workspace.objects.create(name='Templates')
        self.member = Membership.objects.create(workspace=self.workspace, user=self.user, role='owner')
        self.client = APIClient()
        self.client.force_authenticate(self.user, token={'iss': 'https://trusted.example', 'iat': 100})
        self.url = f'/api/v1/workspaces/{self.workspace.pk}/templates/'
        self.body = {'name': 'Inspection', 'items': [
            {'id': 'size', 'label': 'Size', 'required': True, 'allow_na': False},
            {'id': 'fit', 'label': 'Fit', 'required': False, 'allow_na': True},
            {'id': 'finish', 'label': 'Finish', 'required': True, 'allow_na': True},
        ]}

    def publish(self, body=None, key='template-request-0001'):
        return self.client.post(self.url, body or self.body, format='json', HTTP_IDEMPOTENCY_KEY=key)

    def test_retry_returns_original_receipt_even_after_new_version(self):
        first = self.publish()
        self.assertEqual(first.status_code, 201)
        body = {**self.body, 'base_template_id': first.data['id']}
        second = self.publish(body, 'template-request-0002')
        self.assertEqual(second.data['version'], 2)
        retry = self.publish()
        self.assertEqual(retry.status_code, 201)
        self.assertEqual(retry.data, first.data)
        self.assertEqual(CheckTemplate.objects.filter(workspace=self.workspace).count(), 2)
        self.assertEqual(AuditEvent.objects.filter(workspace=self.workspace).count(), 2)

    def test_reused_key_different_content_has_no_side_effect(self):
        self.publish()
        result = self.publish({**self.body, 'name': 'Changed'})
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.data['code'], 'idempotency_conflict')
        self.assertEqual(CheckTemplate.objects.filter(workspace=self.workspace).count(), 1)

    def test_stale_base_is_rejected_and_original_version_unchanged(self):
        first = self.publish()
        update = {**self.body, 'base_template_id': first.data['id'], 'items': list(reversed(self.body['items']))}
        self.assertEqual(self.publish(update, 'template-request-0002').status_code, 201)
        stale = self.publish(update, 'template-request-0003')
        self.assertEqual(stale.status_code, 409)
        self.assertEqual(stale.data['code'], 'template_version_conflict')
        self.assertEqual(stale.data['current']['version'], 2)
        self.assertEqual(CheckTemplate.objects.get(pk=first.data['id']).items, self.body['items'])

    def test_create_same_name_is_not_an_implicit_new_version(self):
        self.publish()
        result = self.publish(key='template-request-0002')
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.data['code'], 'template_name_conflict')

    def test_ids_flags_and_item_order_survive_version_publication(self):
        first = self.publish()
        self.assertEqual(first.data['items'], self.body['items'])
        update = {**self.body, 'base_template_id': first.data['id'], 'items': list(reversed(self.body['items']))}
        result = self.publish(update, 'template-request-0002')
        self.assertEqual(result.data['items'], update['items'])
        event = AuditEvent.objects.get(object_id=str(result.data['id']), action='template.published')
        self.assertEqual(event.details['base_template_id'], first.data['id'])

    def test_revocation_is_checked_before_replaying_a_receipt(self):
        self.publish()
        self.member.role = 'viewer'; self.member.save()
        self.assertEqual(self.publish().status_code, 403)
        self.member.delete()
        self.assertEqual(self.publish().status_code, 404)

    def test_key_required_for_cloud_and_invalid_content_leaves_no_receipt(self):
        self.assertEqual(self.publish(key='').status_code, 400)
        self.assertEqual(self.publish({**self.body, 'items': self.body['items'][:2]}).status_code, 400)
        self.assertFalse(AuditEvent.objects.filter(workspace=self.workspace).exists())
        self.assertEqual(self.publish().status_code, 201)

    def test_cross_workspace_base_cannot_publish_or_reveal_foreign_template(self):
        other = Workspace.objects.create(name='Other')
        foreign = CheckTemplate.objects.create(workspace=other, name='Private template', items=self.body['items'])
        result = self.publish({**self.body, 'base_template_id': foreign.pk})
        self.assertEqual(result.status_code, 409)
        self.assertIsNone(result.data['current'])
        self.assertFalse(CheckTemplate.objects.filter(workspace=self.workspace).exists())
