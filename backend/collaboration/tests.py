import io
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient
from PIL import Image
from PIL import ImageDraw
from .models import Membership, ProductionJob


class WorkflowApiTests(TestCase):
    def setUp(self):
        from django.core.cache import cache
        cache.clear()  # Rate counters must not leak between independent test users reusing a database PK.
        self.owner = get_user_model().objects.create_user(username="owner", password="long-password-123")
        self.client = APIClient()
        self.client.force_authenticate(self.owner)
        response = self.client.post("/api/v1/workspaces/create/", {"name": "Studio"}, format="json")
        self.ws = response.data["id"]

    def to_inspection(self, job_id):
        self.client.patch(f"/api/v1/workspaces/{self.ws}/jobs/{job_id}/", {"status": "printing"}, format="json")
        return self.client.patch(f"/api/v1/workspaces/{self.ws}/jobs/{job_id}/", {"status": "inspection"}, format="json")

    def test_invite_is_single_use_and_viewer_cannot_write(self):
        invite = self.client.post(f"/api/v1/workspaces/{self.ws}/invite/", {"role": "viewer"}, format="json")
        self.assertEqual(invite.status_code, 201)
        viewer = get_user_model().objects.create_user(username="viewer", password="long-password-123")
        other = APIClient()
        other.force_authenticate(viewer)
        redeemed = other.post("/api/v1/workspaces/redeem/", {"code": invite.data["code"]}, format="json")
        self.assertEqual(redeemed.status_code, 201)
        self.assertEqual(other.post("/api/v1/workspaces/redeem/", {"code": invite.data["code"]}, format="json").status_code, 200)
        replay = APIClient(); replay.force_authenticate(get_user_model().objects.create_user(username="replay", password="long-password-123"))
        self.assertEqual(replay.post("/api/v1/workspaces/redeem/", {"code": invite.data["code"]}, format="json").status_code, 404)
        self.assertEqual(other.post(f"/api/v1/workspaces/{self.ws}/jobs/", {"part_name": "A", "printer": "A1", "quantity": 1}, format="json").status_code, 403)

    def test_workspace_isolation_and_job_state_transitions(self):
        own = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/", {"part_name": "Bracket", "printer": "A1", "quantity": 1}, format="json")
        self.assertEqual(own.status_code, 201)
        self.assertEqual(self.client.patch(f"/api/v1/workspaces/{self.ws}/jobs/{own.data['id']}/", {"status": "printing"}, format="json").status_code, 200)
        self.assertEqual(self.client.patch(f"/api/v1/workspaces/{self.ws}/jobs/{own.data['id']}/", {"status": "inspection"}, format="json").status_code, 200)
        self.assertEqual(self.client.patch(f"/api/v1/workspaces/{self.ws}/jobs/{own.data['id']}/", {"status": "closed"}, format="json").status_code, 409)
        stranger = get_user_model().objects.create_user(username="stranger", password="long-password-123")
        another = APIClient(); another.force_authenticate(stranger)
        self.assertEqual(another.get(f"/api/v1/workspaces/{self.ws}/jobs/").status_code, 404)
        self.assertEqual(another.patch(f"/api/v1/workspaces/{self.ws}/jobs/{own.data['id']}/", {"status": "closed"}, format="json").status_code, 404)
        self.assertEqual(another.get(f"/api/v1/workspaces/{self.ws}/members/").status_code, 404)

    def test_job_submission_retry_is_idempotent(self):
        path = f"/api/v1/workspaces/{self.ws}/jobs/"
        fields = {"part_name": "Bracket", "printer": "A1", "quantity": 1}
        first = self.client.post(path, fields, format="json", HTTP_IDEMPOTENCY_KEY="jobrequest-00000001")
        second = self.client.post(path, fields, format="json", HTTP_IDEMPOTENCY_KEY="jobrequest-00000001")
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.data["id"], second.data["id"])
        changed = self.client.post(path, {**fields, "part_name": "Other"}, format="json", HTTP_IDEMPOTENCY_KEY="jobrequest-00000001")
        self.assertEqual(changed.status_code, 409)

    def test_members_list_is_workspace_scoped(self):
        response = self.client.get(f"/api/v1/workspaces/{self.ws}/members/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, [{"id": self.owner.pk, "username": "owner", "display_name": "owner", "role": "owner", "active": True, "is_self": True, "avatar_data": "", "job_title": ""}])

    def test_starter_profiles_are_versioned_and_workspace_overrides_are_owner_only(self):
        url = f"/api/v1/workspaces/{self.ws}/printer-profiles/"
        starters = self.client.get(url)
        self.assertEqual(starters.status_code, 200)
        self.assertEqual({x["id"] for x in starters.data}, {"starter:a1", "starter:p2s"})
        created = self.client.post(url, {"name": "Studio Printer", "version": "4", "source": "https://example.com/profile", "note": "PLA"}, format="json")
        self.assertEqual(created.status_code, 201)
        job = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/", {
            "part_name": "Bracket", "printer": "ignored", "profile_id": created.data["id"], "quantity": 1,
        }, format="json")
        self.assertEqual(job.status_code, 201)
        self.assertEqual(job.data["printer"], "Studio Printer")
        self.assertEqual(job.data["profile_version"], "4")
        self.assertEqual(job.data["profile_source"], "https://example.com/profile")
        viewer = get_user_model().objects.create_user(username="profileviewer", password="long-password-123")
        code = self.client.post(f"/api/v1/workspaces/{self.ws}/invite/", {"role": "viewer"}, format="json").data["code"]
        read_only = APIClient(); read_only.force_authenticate(viewer)
        read_only.post("/api/v1/workspaces/redeem/", {"code": code}, format="json")
        denied = read_only.post(url, {"name": "Other", "version": "1", "source": "https://example.com"}, format="json")
        self.assertEqual(denied.status_code, 403)

    def test_legacy_import_is_explicit_deduplicated_and_excludes_examples_by_default(self):
        url = f"/api/v1/workspaces/{self.ws}/legacy-inspections/"
        rows = [
            {"id": "legacy-1", "at": "2026-10-20T10:00:00Z", "passed": True, "sample": False},
            {"id": "legacy-example", "at": "2026-10-20T11:00:00Z", "passed": True, "sample": True},
        ]
        imported = self.client.post(url, {"records": rows, "include_samples": False}, format="json")
        self.assertEqual(imported.status_code, 201)
        self.assertEqual(imported.data, {"imported": 1, "skipped": 1})
        repeat = self.client.post(url, {"records": rows[:1], "include_samples": False}, format="json")
        self.assertEqual(repeat.data, {"imported": 0, "skipped": 1})
        data = self.client.get(url).data
        self.assertEqual(data["count"], 1)
        self.assertEqual(data["sample_count"], 0)
        self.assertEqual(data["records"][0]["id"], "legacy-1")

    def test_imported_history_retains_original_and_final_review_results(self):
        url = f"/api/v1/workspaces/{self.ws}/legacy-inspections/"
        rows = [
            {"id": "review-pass", "at": "2026-10-23T10:00:00Z", "passed": False, "review": "pass", "sample": False},
            {"id": "review-fail", "at": "2026-10-23T10:00:00Z", "passed": True, "review": "fail", "sample": False},
        ]
        response = self.client.post(url, {"records": rows}, format="json")
        self.assertEqual(response.status_code, 201)
        data = {row['id']: row for row in self.client.get(url).data['records']}
        self.assertTrue(data['review-pass']['passed'])
        self.assertFalse(data['review-pass']['original_passed'])
        self.assertFalse(data['review-fail']['passed'])
        self.assertTrue(data['review-fail']['original_passed'])

    def test_rejects_fake_image_payload(self):
        job = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/", {"part_name": "Bracket", "printer": "A1", "quantity": 1}, format="json").data
        self.to_inspection(job["id"])
        upload = SimpleUploadedFile("photo.png", b"not actually a png", content_type="image/png")
        response = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/", {"image": upload}, format="multipart")
        self.assertEqual(response.status_code, 400)

    def test_valid_image_exception_and_resolution(self):
        job = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/", {"part_name": "Bracket", "printer": "A1", "quantity": 1}, format="json").data
        self.to_inspection(job["id"])
        buffer = io.BytesIO()
        source = Image.new("RGB", (32, 24), "white")
        ImageDraw.Draw(source).rectangle((6, 5, 25, 18), outline="black", width=2)
        source.save(buffer, format="PNG")
        upload = SimpleUploadedFile("part.png", buffer.getvalue(), content_type="image/png")
        key = "a" * 64
        result = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/", {"image": upload}, format="multipart", HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(result.status_code, 201)
        preview = self.client.get(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/{result.data['id']}/preview/")
        self.assertEqual(preview.status_code, 200)
        self.assertEqual(preview["Content-Type"], "image/png")
        preview_bytes = b"".join(preview.streaming_content)
        preview_image = Image.open(io.BytesIO(preview_bytes)).convert("RGB")
        self.assertEqual(preview_image.getpixel((0, 0)), (255, 255, 255))
        self.assertIn((52, 120, 246), set(preview_image.getdata()))
        original = self.client.get(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/{result.data['id']}/original/")
        self.assertEqual(original.status_code, 200)
        self.assertEqual(original["Content-Type"], "image/png")
        duplicate = SimpleUploadedFile("part.png", buffer.getvalue(), content_type="image/png")
        again = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/evidence/", {"image": duplicate}, format="multipart", HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(again.status_code, 200)
        self.assertEqual(again.data["id"], result.data["id"])
        case = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/exceptions/", {"note": "边缘需要复核"}, format="json")
        self.assertEqual(case.status_code, 201)
        resolved = self.client.post(f"/api/v1/workspaces/{self.ws}/exceptions/{case.data['id']}/resolve/", {"resolution": "已复核", "next_status": "closed", "disposition": "concession", "closure_reason": "管理员复核后授权让步放行"}, format="json")
        self.assertEqual(resolved.status_code, 200)
        self.assertEqual(resolved.data["job_status"], "closed")
        self.assertEqual(self.client.get(f"/api/v1/workspaces/{self.ws}/jobs/").data[0]["inspections"][0]["verdict"], "fail")

    def test_human_pass_decision_closes_job_with_audit_record(self):
        job = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/", {"part_name": "Clip", "printer": "A1", "quantity": 1}, format="json").data
        self.to_inspection(job["id"])
        result = self.client.post(f"/api/v1/workspaces/{self.ws}/jobs/{job['id']}/inspection/", {"verdict": "pass"}, format="json")
        self.assertEqual(result.status_code, 201)
        self.assertEqual(result.data["status"], "closed")
        self.assertEqual(result.data["inspections"][0]["verdict"], "pass")

    def test_login_issues_bearer_token(self):
        anonymous = APIClient()
        response = anonymous.post("/api/v1/auth/login/", {"username": "owner", "password": "long-password-123"}, format="json")
        self.assertEqual(response.status_code, 200)
        anonymous.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
        self.assertEqual(anonymous.get("/api/v1/workspaces/").status_code, 200)


class ProductBatchTests(TestCase):
    setUp = WorkflowApiTests.setUp
    to_inspection = WorkflowApiTests.to_inspection
    def test_template_snapshot_piece_metrics_serials_and_scoped_reports(self):
        from .models import CheckTemplate
        base = f'/api/v1/workspaces/{self.ws}/'
        templates = self.client.get(base + 'templates/').data
        self.assertEqual(len(templates), 3)
        template = templates[0]
        body = {'part_name': 'Batch fixture', 'printer': 'A1', 'quantity': 2,
                'batch_code': 'B-24', 'tracking_mode': 'serial', 'serial_numbers': ['SN-A', 'SN-B'],
                'template_id': template['id']}
        created = self.client.post(base + 'jobs/', body, format='json')
        self.assertEqual(created.status_code, 201, created.data)
        job = created.data['id']; url = base + f'jobs/{job}/inspection/'
        duplicate = self.client.post(base + 'jobs/', body, format='json')
        self.assertEqual(duplicate.status_code, 409)
        self.to_inspection(job)
        answers = [{'id': item['id'], 'result': 'pass', 'note': ''} for item in template['items']]
        check = {'verdict': 'pass', 'template_id': template['id'], 'answers': answers,
                 'inspected_qty': 2, 'pass_qty': 2, 'fail_qty': 0, 'scrap_qty': 0,
                 'serial_results': {'SN-A': 'pass', 'SN-B': 'pass'}}
        self.assertEqual(self.client.post(url, {**check, 'pass_qty': 3}, format='json').status_code, 400)
        self.assertEqual(self.client.post(url, {**check, 'answers': []}, format='json').status_code, 400)
        self.assertEqual(self.client.post(url, {**check, 'evidence_ids': [{}]}, format='json').status_code, 400)
        completed = self.client.post(url, check, format='json')
        self.assertEqual(completed.status_code, 201, completed.data)
        records = self.client.get(base + 'records/').data
        self.assertEqual(records[0]['round_no'], 1)
        self.assertEqual(records[0]['template_snapshot']['items'], template['items'])
        CheckTemplate.objects.filter(pk=template['id']).update(name='Changed fixture')
        self.assertEqual(self.client.get(base + 'records/').data[0]['template_snapshot']['name'], template['name'])
        metrics = self.client.get(base + 'metrics/').data
        self.assertEqual(metrics['first_inspected_pieces'], 2)
        self.assertEqual(metrics['first_pass_rate'], 1)
        self.assertEqual(metrics['final_release_rate'], 1)
        self.assertEqual(self.client.get(base + 'report/?download=csv').status_code, 200)
        self.assertEqual(self.client.get(base + 'metrics/?q=absent').data['first_pass_rate'], None)
        self.assertEqual(self.client.get(base + 'records/?q=B-24').data[0]['id'], records[0]['id'])
        stranger = APIClient(); stranger.force_authenticate(get_user_model().objects.create_user(username='outsider'))
        for endpoint in ['records/', 'metrics/', 'templates/', 'report/', 'notifications/']:
            self.assertEqual(stranger.get(base + endpoint).status_code, 404)

    def test_upload_receipt_checks_content_stage_actor_and_cross_job(self):
        job = self.client.post(f'/api/v1/workspaces/{self.ws}/jobs/', {'part_name': 'Photo', 'printer': 'A1', 'quantity': 1}, format='json').data['id']
        self.to_inspection(job)
        stream = io.BytesIO(); Image.new('RGB', (20, 20), 'white').save(stream, format='PNG')
        data = stream.getvalue(); key = 'a' * 64
        url = f'/api/v1/workspaces/{self.ws}/jobs/{job}/evidence/'
        def upload(raw=data, stage='inspection'):
            return self.client.post(url, {'image': SimpleUploadedFile('x.png', raw, content_type='image/png'), 'stage': stage}, format='multipart', HTTP_IDEMPOTENCY_KEY=key)
        first = upload(); self.assertEqual(first.status_code, 201, first.data)
        self.assertEqual(upload().data['id'], first.data['id'])
        self.assertEqual(upload(stage='after').status_code, 409)
        changed = io.BytesIO(); Image.new('RGB', (20,20), 'red').save(changed, format='PNG')
        self.assertEqual(upload(changed.getvalue()).status_code, 409)


class NotificationTests(TestCase):
    setUp = WorkflowApiTests.setUp
    to_inspection = WorkflowApiTests.to_inspection

    def test_read_is_per_user_versioned_and_workspace_scoped(self):
        base = f'/api/v1/workspaces/{self.ws}/'
        job = self.client.post(base + 'jobs/', {'part_name': 'Notice', 'printer': 'A1', 'quantity': 1}, format='json').data['id']
        self.to_inspection(job)
        notice = self.client.get(base + 'notifications/').data[0]
        self.assertFalse(notice['read'])
        url = base + f'notifications/{job}/read/'
        self.assertEqual(self.client.post(url, {'version': notice['version']}, format='json').status_code, 200)
        self.assertTrue(self.client.get(base + 'notifications/').data[0]['read'])
        ProductionJob.objects.filter(pk=job).update(version=notice['version'] + 1)
        self.assertFalse(self.client.get(base + 'notifications/').data[0]['read'])
        self.client.post(url, {'version': 1}, format='json')
        from .models import NotificationReceipt
        self.assertEqual(NotificationReceipt.objects.get(job_id=job).version, notice['version'])
        other = APIClient(); other.force_authenticate(get_user_model().objects.create_user(username='other-notice'))
        self.assertEqual(other.post(url, {'version': 1}, format='json').status_code, 404)
        self.assertEqual(self.client.post(url, {'version': True}, format='json').status_code, 400)

    def test_assignments_include_queued_and_printing_without_unassigned_noise(self):
        base = f'/api/v1/workspaces/{self.ws}/'
        expected = set()
        for state in ['queued', 'printing', 'inspection', 'exception', 'closed']:
            assigned = ProductionJob.objects.create(workspace_id=self.ws, part_name=state, printer='A1', quantity=1, status=state, assignee=self.owner)
            unassigned = ProductionJob.objects.create(workspace_id=self.ws, part_name='Shared '+state, printer='A1', quantity=1, status=state)
            if state != 'closed': expected.add(str(assigned.pk))
            if state in ['inspection', 'exception']: expected.add(str(unassigned.pk))
        rows = self.client.get(base+'notifications/').data
        self.assertEqual({row['task_id'] for row in rows}, expected)
        self.assertTrue(all(row['read'] is False for row in rows))

    def test_reassignment_removes_previous_recipients_access_to_read_receipt(self):
        from .models import NotificationReceipt
        base = f'/api/v1/workspaces/{self.ws}/'
        job = ProductionJob.objects.create(workspace_id=self.ws, part_name='Assigned', printer='A1', quantity=1, status='queued', assignee=self.owner)
        new_user = get_user_model().objects.create_user(username='next-recipient')
        Membership.objects.create(workspace_id=self.ws, user=new_user, role='operator')
        url = base+f'notifications/{job.pk}/read/'
        self.assertEqual(self.client.post(url, {'version': 1}, format='json').status_code, 200)
        ProductionJob.objects.filter(pk=job.pk).update(assignee=new_user, version=2)
        self.assertEqual(self.client.get(base+'notifications/').data, [])
        self.assertEqual(self.client.post(url, {'version': 1}, format='json').status_code, 404)
        next_client = APIClient(); next_client.force_authenticate(new_user)
        self.assertFalse(next_client.get(base+'notifications/').data[0]['read'])
        for unused in range(2):
            self.assertEqual(next_client.post(url, {'version': 2}, format='json').status_code, 200)
        self.assertEqual(NotificationReceipt.objects.filter(user=new_user, job=job).count(), 1)
        self.assertTrue(next_client.get(base+'notifications/').data[0]['read'])


class QueryScopeTests(TestCase):
    setUp = WorkflowApiTests.setUp
    to_inspection = WorkflowApiTests.to_inspection

    def test_shared_filters_do_not_duplicate_tasks_and_report_exports_match(self):
        import csv
        from django.utils import timezone
        from datetime import timedelta
        base = f'/api/v1/workspaces/{self.ws}/'
        created = []
        for name, batch in [('Scope target', 'BATCH-QUERY'), ('Outside scope', 'OTHER')]:
            job = self.client.post(base + 'jobs/', {'part_name': name, 'printer': 'A1', 'quantity': 2, 'batch_code': batch}, format='json').data
            self.to_inspection(job['id'])
            response = self.client.post(base + f"jobs/{job['id']}/inspection/", {'verdict': 'pass', 'inspected_qty': 2, 'pass_qty': 2, 'fail_qty': 0, 'scrap_qty': 0}, format='json')
            self.assertEqual(response.status_code, 201, response.data)
            created.append(job)
        target = ProductionJob.objects.get(pk=created[0]['id'])
        target.assignee = self.owner
        target.save(update_fields=['assignee'])
        from .models import ExceptionCase
        for index in range(2):
            ExceptionCase.objects.create(job=target, category='surface', note=f'Archived issue {index}', status='resolved')
        now = timezone.now()
        params = {'category': 'surface', 'q': 'BATCH-QUERY', 'status': 'closed', 'assignee': self.owner.pk, 'inspector': self.owner.pk, 'verdict': 'pass', 'from': (now-timedelta(days=1)).isoformat(), 'to': (now+timedelta(days=1)).isoformat()}
        jobs = self.client.get(base + 'jobs/', params).data
        self.assertEqual([job['id'] for job in jobs], [str(target.pk)])
        record = self.client.get(base + 'records/', params).data
        self.assertEqual(len(record), 1)
        metrics = self.client.get(base + 'metrics/', params).data
        report = self.client.get(base + 'report/', params).data
        self.assertEqual(metrics, report['metrics'])
        self.assertEqual(metrics['task_ids'], [str(target.pk)])
        self.assertEqual(metrics['first_inspected_pieces'], 2)
        self.assertEqual([job['id'] for job in report['jobs']], [str(target.pk)])
        self.assertEqual(report['source'], 'cloud')
        self.assertEqual(report['filters']['q'], 'BATCH-QUERY')
        self.assertTrue(report['report_id'].startswith('LS-'))
        export = self.client.get(base + 'report/', {**params, 'download': 'csv'})
        rows = list(csv.reader(io.StringIO(export.content.decode('utf-8-sig'))))
        self.assertIn(['first_inspected_pieces', '2'], rows)
        self.assertIn(str(target.pk), export.content.decode('utf-8-sig'))
        self.assertNotIn(created[1]['id'], export.content.decode('utf-8-sig'))
        for bad in [{'assignee': 'invalid'}, {'inspector': '99999999999999999999999999'}, {'status': 'invalid'}, {'from': '2026-10-23'}]:
            self.assertEqual(self.client.get(base + 'metrics/', bad).status_code, 400)

    def test_inspection_range_and_first_round_drilldown_use_real_round_dates(self):
        from datetime import datetime, timezone, timedelta
        from .models import QualityInspection
        base = f'/api/v1/workspaces/{self.ws}/'
        job = self.client.post(base + 'jobs/', {'part_name': 'Dates', 'printer': 'A1', 'quantity': 2}, format='json').data
        self.to_inspection(job['id'])
        path = base + f"jobs/{job['id']}/inspection/"
        self.assertEqual(self.client.post(path, {'verdict':'pass', 'inspected_qty':2, 'pass_qty':2, 'fail_qty':0, 'scrap_qty':0}, format='json').status_code, 201)
        first = QualityInspection.objects.get(job_id=job['id'])
        first_time = datetime(2026,10,22,23,59,tzinfo=timezone.utc)
        QualityInspection.objects.filter(pk=first.pk).update(created_at=first_time)
        second = QualityInspection.objects.create(job_id=job['id'], inspector=self.owner, round_no=2, verdict='pass', inspected_qty=2, pass_qty=2, fail_qty=0, scrap_qty=0)
        QualityInspection.objects.filter(pk=second.pk).update(created_at=first_time+timedelta(minutes=11))
        filters = {'inspected_from':'2026-10-23T00:00:00Z', 'inspected_to':'2026-10-24T00:00:00Z', 'inspector':self.owner.pk}
        records = self.client.get(base+'records/', filters).data
        self.assertEqual([row['round_no'] for row in records], [2])
        self.assertEqual(len(self.client.get(base+'jobs/', filters).data), 1)
        report = self.client.get(base+'report/', filters).data
        self.assertEqual(report['filters']['inspected_from'], filters['inspected_from'])
        self.assertEqual(report['metrics']['first_inspected_pieces'], 2)
        self.assertEqual(len(report['jobs'][0]['inspections']), 2)
        self.assertEqual(len(self.client.get(base+'jobs/', {'first_day':'2026-10-22'}).data), 1)
        self.assertEqual(self.client.get(base+'jobs/', {'first_day':'2026-10-23'}).data, [])
        for invalid in [{'first_day':'2026-02-30'}, {'inspected_from':'2026-13-01T00:00:00Z'}, {'inspected_from':'2026-10-23'}, {'inspected_from':'2026-10-24T00:00:00Z','inspected_to':'2026-10-23T00:00:00Z'}]:
            self.assertEqual(self.client.get(base+'records/', invalid).status_code, 400)


class WorkbenchDateTests(TestCase):
    setUp = WorkflowApiTests.setUp

    def test_local_day_update_bounds_are_shared_across_lists_metrics_and_exports(self):
        from datetime import datetime, timezone
        base = f'/api/v1/workspaces/{self.ws}/'
        ids = []
        for hour in [15, 16]:
            response = self.client.post(base+'jobs/', {'part_name': f'Day boundary {hour}', 'printer':'A1', 'quantity':1}, format='json')
            self.assertEqual(response.status_code, 201)
            ids.append(response.data['id'])
            ProductionJob.objects.filter(pk=ids[-1]).update(updated_at=datetime(2026,10,22,hour,0,tzinfo=timezone.utc))
        filters = {'updated_from':'2026-10-22T16:00:00Z', 'updated_to':'2026-10-23T16:00:00Z'}
        self.assertEqual([j['id'] for j in self.client.get(base+'jobs/', filters).data], ids[1:])
        self.assertEqual(self.client.get(base+'metrics/', filters).data['task_ids'], ids[1:])
        report = self.client.get(base+'report/', filters).data
        self.assertEqual(report['filters'], filters)
        self.assertEqual([j['id'] for j in report['jobs']], ids[1:])
        csv = self.client.get(base+'report/', {**filters, 'download':'csv'}).content.decode('utf-8-sig')
        self.assertIn('updated_from', csv)
        for bad in [{'updated_from':'2026-10-23'}, {'updated_from':filters['updated_to'],'updated_to':filters['updated_from']}]:
            self.assertEqual(self.client.get(base+'jobs/',bad).status_code,400)
        other = APIClient(); other.force_authenticate(get_user_model().objects.create_user(username='workbench-outsider'))
        self.assertEqual(other.get(base+'jobs/', filters).status_code,404)


class HistoryProjectionTests(TestCase):
    setUp = WorkflowApiTests.setUp
    to_inspection = WorkflowApiTests.to_inspection

    def test_history_has_record_provenance_without_rewriting_sparse_legacy_events(self):
        from .models import AuditEvent, QualityInspection
        base = f'/api/v1/workspaces/{self.ws}/'
        job = self.client.post(base+'jobs/', {'part_name':'History batch','printer':'A1','quantity':2}, format='json').data
        self.to_inspection(job['id'])
        key='history-inspection-00001'
        payload={'version':3,'verdict':'fail','note':'Surface mark','inspected_qty':2,'pass_qty':1,'fail_qty':1,'scrap_qty':0}
        url=base+f"jobs/{job['id']}/inspection/"
        response=self.client.post(url,payload,format='json',HTTP_IDEMPOTENCY_KEY=key)
        self.assertEqual(response.status_code,201,response.data)
        self.assertEqual(self.client.post(url,payload,format='json',HTTP_IDEMPOTENCY_KEY=key).status_code,201)
        check=QualityInspection.objects.get(job_id=job['id'])
        # Old rows may have only a verdict. Read projection must not mutate them.
        sparse=AuditEvent.objects.create(workspace_id=self.ws,job_id=job['id'],user=self.owner,action='inspection.fail',object_id=str(check.pk),details={'verdict':'fail'})
        original=list(AuditEvent.objects.filter(job_id=job['id']).values())
        history=self.client.get(base+f"jobs/{job['id']}/history/").data
        self.assertEqual(len(history),len(original))
        event=next(e for e in history if e['action']=='inspection.fail' and e['id']!=sparse.pk)
        self.assertEqual(event['details']['previous'],'inspection')
        self.assertEqual(event['details']['status'],'exception')
        self.assertEqual(event['record']['round_no'],1)
        self.assertEqual(event['record']['pass_qty'],1)
        self.assertEqual(event['actor_id'],self.owner.pk)
        self.assertEqual(event['workspace_id'],self.ws)
        legacy=next(e for e in history if e['id']==sparse.pk)
        self.assertEqual(legacy['details'],{'verdict':'fail'})
        self.assertEqual(legacy['record']['fail_qty'],1)
        self.assertEqual(original,list(AuditEvent.objects.filter(job_id=job['id']).values()))
        foreign=APIClient(); foreign.force_authenticate(get_user_model().objects.create_user(username='history-foreign'))
        self.assertEqual(foreign.get(base+f"jobs/{job['id']}/history/").status_code,404)
