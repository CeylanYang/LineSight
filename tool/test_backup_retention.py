import datetime as dt
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from backup_retention import expire, select_expired

NOW = dt.datetime(2026, 10, 24, tzinfo=dt.timezone.utc)


def stamp(moment):
    return moment.strftime('%Y%m%dT%H%M%S%fZ')


class RetentionTest(unittest.TestCase):
    def test_sparse_history_keeps_seven_distinct_days(self):
        values = [stamp(NOW-dt.timedelta(days=i*80)) for i in range(7)]
        self.assertEqual(select_expired(values, NOW), [])

    def test_daily_weekly_monthly_anchors_and_recent_snapshots(self):
        values = [stamp(NOW-dt.timedelta(days=i)) for i in range(800)]
        expired = set(select_expired(values, NOW))
        self.assertTrue(expired)
        self.assertFalse(expired.intersection(values[:31]))
        keep = set(values)-expired
        months = {(dt.datetime.strptime(v,'%Y%m%dT%H%M%S%fZ').year,
                   dt.datetime.strptime(v,'%Y%m%dT%H%M%S%fZ').month) for v in keep}
        self.assertGreaterEqual(len(months), 12)
        self.assertIn(values[-1], expired)

    def fixture(self, root, value, server=False):
        folder = root/value; folder.mkdir()
        raw = b'encrypted-fixture'
        (folder/'portable-backup.lsbk').write_bytes(raw)
        report = {'backup':value, 'off_host_copy_verified':True,
                  'all_file_hashes_verified':True,'authentication_tag_verified':True,
                  'archive_sha256':hashlib.sha256(raw).hexdigest()}
        (folder/('offhost-verified.json' if server else 'verification.json')).write_text(json.dumps(report))
        if server:
            (folder/'report.json').write_text(json.dumps({'mode':'backup'}))
        else:
            (root/'keys').mkdir(exist_ok=True)
            (root/'keys'/(value+'.bin')).write_bytes(b'k'*32)
        return folder

    def test_local_apply_preserves_anchors_and_removes_only_expired_pair(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve()
            for i in range(400): self.fixture(root,stamp(NOW-dt.timedelta(days=i)))
            preview=expire(root,now=NOW)
            self.assertTrue(preview['expiry_candidates'])
            self.assertFalse(preview['removed'])
            result=expire(root,apply=True,now=NOW)
            self.assertEqual(result['removed'],preview['expiry_candidates'])
            for value in result['removed']:
                self.assertFalse((root/value).exists())
                self.assertFalse((root/'keys'/(value+'.bin')).exists())
            self.assertTrue((root/stamp(NOW)).exists())

    def test_unverified_corrupt_rehearsal_and_unknown_snapshots_survive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve()
            for i in range(15): self.fixture(root,stamp(NOW-dt.timedelta(days=i*40)),server=True)
            protected=[]
            for i,kind in enumerate(['unverified','corrupt','rehearsal','link']):
                value=stamp(NOW-dt.timedelta(days=1000+i))
                folder=self.fixture(root,value,server=True); protected.append(folder)
                if kind=='unverified':(folder/'offhost-verified.json').unlink()
                if kind=='corrupt':(folder/'portable-backup.lsbk').write_bytes(b'changed')
                if kind=='rehearsal':(folder/'restored-identity').mkdir()
                if kind=='link':
                    try:(folder/'outside').symlink_to(root/'not-a-snapshot')
                    except OSError:(folder/'offhost-verified.json').unlink()
            result=expire(root,server=True,apply=True,now=NOW)
            self.assertTrue(result['removed'])
            self.assertTrue(all(p.exists() for p in protected))


if __name__=='__main__': unittest.main()
