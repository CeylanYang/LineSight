from datetime import date, datetime, timedelta, timezone as datetime_timezone
from io import StringIO
from unittest.mock import patch
from django.core.management import call_command
from django.core.management.base import CommandError
from django.contrib.auth import get_user_model
from django.test import TestCase
from django.test.utils import CaptureQueriesContext
from django.db import connection
from django.utils import timezone
from rest_framework.test import APIClient
from .dispatch import dispatch, SLOTS
from .models import Workspace, Membership, WorkspaceBulletin, ProductionJob, CheckTemplate, QualityInspection

class DispatchTests(TestCase):
    def setUp(self):
        self.workspace=Workspace.objects.create(name='展示团队',dispatch_enabled=True)
        self.other=Workspace.objects.create(name='真实团队')
        self.user=get_user_model().objects.create_user(username='reader',password='test-password')
        self.second=get_user_model().objects.create_user(username='second',password='test-password')
        for user in [self.user,self.second]: Membership.objects.create(workspace=self.workspace,user=user,role='operator')
        self.client=APIClient(HTTP_X_LINESIGHT_FEATURES="workspace-bulletins-v1");self.client.force_authenticate(self.user)
        self.day=date(2026,1,2)
        self.base=f'/api/v1/workspaces/{self.workspace.pk}/'
    def test_daily_twenty_deduplicated_and_linked(self):
        self.assertEqual([dispatch(self.workspace.pk,self.day,s) for s in SLOTS],[7,6,7])
        self.assertEqual(dispatch(self.workspace.pk,self.day,9),0)
        self.assertEqual(WorkspaceBulletin.objects.count(),20)
        self.assertEqual(ProductionJob.objects.count(),6)
        self.assertEqual(CheckTemplate.objects.filter(workspace=self.workspace).count(),3)
        self.assertEqual(WorkspaceBulletin.objects.filter(kind='task',job__isnull=False).count(),6)
        self.assertEqual(WorkspaceBulletin.objects.filter(kind='template',template__isnull=False).count(),3)
        self.assertFalse(WorkspaceBulletin.objects.filter(body__contains='{').exists())
    def test_checklist_bulletins_describe_the_actual_linked_batches(self):
        for slot in SLOTS:
            dispatch(self.workspace.pk, self.day, slot)
        for notice in WorkspaceBulletin.objects.filter(kind='template'):
            jobs = list(ProductionJob.objects.filter(template=notice.template))
            self.assertEqual(len(jobs), 2)
            self.assertIn('生产巡检', notice.title)
            for job in jobs:
                self.assertIn(job.batch_code, notice.body)
                self.assertEqual(job.workspace_id, notice.workspace_id)
                self.assertEqual(job.template_id, notice.template_id)
            task_notices = WorkspaceBulletin.objects.filter(kind='task', job__in=jobs)
            self.assertEqual(task_notices.count(), 2)

    def test_dispatched_job_uses_required_checklist_through_inspection(self):
        dispatch(self.workspace.pk, self.day, 9)
        job = ProductionJob.objects.filter(workspace=self.workspace).order_by('batch_code').first()
        path = self.base + f'jobs/{job.pk}/'
        detail = self.client.get(path)
        self.assertEqual(detail.status_code, 200)
        template = detail.data['template']
        self.assertEqual(template['id'], job.template_id)
        for version, target in [(1, 'printing'), (2, 'inspection')]:
            result = self.client.patch(path, {'version': version, 'status': target}, format='json', HTTP_IDEMPOTENCY_KEY=f'dispatch-transition-{version}')
            self.assertEqual(result.status_code, 200, result.data)
        key = 'dispatch-inspection-0001'
        incomplete = self.client.post(path + 'inspection/', {'version': 3, 'verdict': 'pass', 'answers': []}, format='json', HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(incomplete.status_code, 400)
        job.refresh_from_db()
        self.assertEqual((job.status, job.version), ('inspection', 3))
        answers = [{'id': item['id'], 'result': 'pass'} for item in template['items']]
        payload = {'version': 3, 'verdict': 'pass', 'answers': answers}
        result = self.client.post(path + 'inspection/', payload, format='json', HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(result.status_code, 201, result.data)
        replay = self.client.post(path + 'inspection/', payload, format='json', HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(replay.data, result.data)
        job.refresh_from_db()
        self.assertEqual((job.status, job.version), ('closed', 4))
        check = QualityInspection.objects.get(job=job)
        self.assertEqual(check.template_snapshot['id'], template['id'])
        self.assertEqual(check.template_snapshot['items'], template['items'])
        self.assertEqual(check.answers, answers)

    def test_notification_queries_stay_bounded_and_recent_announcements_keep_receipts(self):
        jobs = []
        for index in range(15):
            job = ProductionJob.objects.create(workspace=self.workspace, part_name=f'Pending {index}', quantity=1, status='inspection')
            jobs.append(job)
        QualityInspection.objects.create(job=jobs[0], inspector=self.user, verdict='fail')
        at = timezone.now() - timedelta(days=1)
        notices = []
        for index in range(125):
            notices.append(self.workspace.bulletins.create(source_key=f'load/{index}', title=f'Notice {index}', body='Body', published_at=at + timedelta(seconds=index)))
        notices[-1].read_by.add(self.user)
        notices[0].read_by.add(self.user)
        with CaptureQueriesContext(connection) as queries:
            response = self.client.get(self.base + 'notifications/')
        self.assertEqual(response.status_code, 200)
        self.assertLessEqual(len(queries), 6)
        bulletins = [row for row in response.data if row.get('bulletin')]
        self.assertEqual(len(bulletins), 120)
        self.assertEqual(bulletins[0]['part_name'], 'Notice 124')
        self.assertTrue(bulletins[0]['read'])
        self.assertFalse(any(row['part_name'] == 'Notice 0' for row in bulletins))
        task_rows = {row['task_id']: row for row in response.data if not row.get('bulletin')}
        self.assertTrue(task_rows[str(jobs[0].pk)]['reinspection'])
        self.assertFalse(task_rows[str(jobs[1].pk)]['reinspection'])

    def test_disabled_workspace_and_variation(self):
        with self.assertRaises(ValueError):dispatch(self.other.pk,self.day,9)
        dispatch(self.workspace.pk,self.day,9)
        first=list(WorkspaceBulletin.objects.values_list('body',flat=True))
        dispatch(self.workspace.pk,self.day+timedelta(days=1),9)
        self.assertEqual(WorkspaceBulletin.objects.count(),14)
        self.assertGreater(len(set(WorkspaceBulletin.objects.values_list('body',flat=True))),len(first))
        self.assertFalse(self.other.bulletins.exists())
    def test_membership_future_visibility_and_per_user_receipt(self):
        dispatch(self.workspace.pk,self.day,9)
        future=self.workspace.bulletins.create(source_key='future',title='Later',body='Not yet',published_at=timezone.now()+timedelta(days=1))
        response=self.client.get(self.base+'notifications/')
        self.assertEqual(response.status_code,200);self.assertEqual(len(response.data),7)
        notice=response.data[0]
        self.assertFalse(notice['read']);self.assertTrue(notice['bulletin'])
        url=self.base+f"notifications/{notice['id']}/read/"
        self.assertEqual(self.client.post(url,{'version':1},format='json').status_code,200)
        self.assertEqual(self.client.post(url,{'version':1},format='json').status_code,200)
        self.assertTrue(next(n for n in self.client.get(self.base+'notifications/').data if n['id']==notice['id'])['read'])
        self.client.force_authenticate(self.second)
        self.assertFalse(next(n for n in self.client.get(self.base+'notifications/').data if n['id']==notice['id'])['read'])
        self.assertEqual(self.client.post(self.base+f'notifications/{future.pk}/read/',{'version':1},format='json').status_code,404)
        self.assertEqual(self.client.get(f'/api/v1/workspaces/{self.other.pk}/notifications/').status_code,404)
    def test_older_clients_keep_task_only_notification_contract(self):
        dispatch(self.workspace.pk,self.day,9)
        client=APIClient();client.force_authenticate(self.user)
        self.assertEqual(client.get(self.base+'notifications/').data,[])

    def test_unauthed_and_foreign_id_cannot_mark(self):
        row=self.other.bulletins.create(source_key='foreign',title='Private',body='Private',published_at=timezone.now())
        self.assertEqual(self.client.post(self.base+f'notifications/{row.pk}/read/',{'version':1},format='json').status_code,404)
        self.client.force_authenticate(None)
        self.assertEqual(self.client.get(self.base+'notifications/').status_code,401)


class DispatchCommandTests(TestCase):
    def setUp(self):
        self.team = Workspace.objects.create(name='Scheduled', dispatch_enabled=True)
        self.disabled = Workspace.objects.create(name='Disabled')

    def run_at(self, hour, minute=0, **options):
        # UTC input verifies the command uses Beijing time even on a UTC host.
        instant = datetime(2026, 1, 2, hour - 8, minute, tzinfo=datetime_timezone.utc)
        output = StringIO()
        with patch('collaboration.management.commands.dispatch_workspace.timezone.now', return_value=instant):
            call_command('dispatch_workspace', stdout=output, **options)
        return output.getvalue()

    def test_exact_boundaries_and_repeated_runs(self):
        for hour, minute, expected, added in [(8, 59, 0, 0), (9, 0, 7, 7), (11, 59, 7, 0), (12, 0, 13, 6), (17, 59, 13, 0), (18, 0, 20, 7)]:
            with self.subTest(hour=hour, minute=minute):
                self.assertIn(f'published={added};', self.run_at(hour, minute))
                self.assertEqual(WorkspaceBulletin.objects.count(), expected)
                self.assertIn('published=0;', self.run_at(hour, minute))
        self.assertFalse(self.disabled.bulletins.exists())

    def test_late_restart_catches_up_today_only(self):
        self.assertIn('published=20;', self.run_at(23))
        self.assertEqual(WorkspaceBulletin.objects.count(), 20)
        self.assertEqual(set(WorkspaceBulletin.objects.values_list('published_at__date', flat=True)), {date(2026, 1, 2)})
        self.assertEqual(ProductionJob.objects.count(), 6)
        self.assertEqual(CheckTemplate.objects.filter(workspace=self.team).count(), 3)
        self.assertIn('published=0;', self.run_at(23))

    def test_explicit_future_slot_or_day_cannot_publish(self):
        self.assertIn('published=0;', self.run_at(9, slot=18))
        with self.assertRaises(CommandError):
            self.run_at(9, date=date(2026, 1, 3))
        self.assertEqual(WorkspaceBulletin.objects.count(), 0)

    def test_target_workspace_does_not_publish_other_teams(self):
        second = Workspace.objects.create(name='Other enabled', dispatch_enabled=True)
        self.assertIn('published=7; workspaces=1;', self.run_at(9, workspace=self.team.pk))
        self.assertEqual(self.team.bulletins.count(), 7)
        self.assertFalse(second.bulletins.exists())
        self.assertIn('published=0; workspaces=0;', self.run_at(18, workspace=self.disabled.pk))
