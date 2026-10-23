import json
import subprocess
import sys
from pathlib import Path
from urllib.request import Request,urlopen
sys.path.insert(0,'/opt/linesight-identity/api-cutover')
from rehearse_cloud_restore import Provider
provider=Provider()
remaining=int(provider.sql(provider.database,"SELECT count(*) FROM pg_database WHERE datname LIKE 'linesight_restore_%'"))
assert remaining==0
containers=subprocess.check_output(['podman','ps','--format','{{.Names}}'],text=True).splitlines()
assert set(containers)=={'linesight-identity_postgres_1','linesight-identity_keycloak_1'}
listeners=subprocess.check_output(['ss','-ltnH'],text=True)
assert not any(line.split()[3].endswith(':18081') for line in listeners.splitlines())
assert not Path('/root/linesight-restore-private/export-key.bin').exists()
with urlopen(Request('http://127.0.0.1:8000/',headers={'Host':'47.111.81.94','X-Forwarded-Proto':'https'}),timeout=10) as response:
    assert json.load(response)['status']=='ready'
with urlopen('https://47.111.81.94/sso/realms/linesight/.well-known/openid-configuration',timeout=15) as response:
    assert json.load(response)['issuer']=='https://47.111.81.94/sso/realms/linesight'
active=subprocess.check_output(['systemctl','is-active','linesight-cloud-backup.timer'],text=True).strip()
assert active=='active'
assert subprocess.check_output(['systemctl','show','linesight-cloud-backup.service','-p','Result','--value'],text=True).strip()=='success'
next_run=subprocess.check_output(['systemctl','show','linesight-cloud-backup.timer','-p','NextElapseUSecRealtime','--value'],text=True).strip()
latest=max(Path('/var/backups/linesight/complete').iterdir(),key=lambda p:p.name)
assert (latest.stat().st_mode&0o777)==0o700
assert all((p.stat().st_mode&0o777)==(0o700 if p.is_dir() else 0o600) for p in latest.rglob('*'))
print(json.dumps({'api_health':True,'live_provider_discovery':True,'temporary_restore_databases_remaining':remaining,'temporary_identity_listener_remaining':False,'only_production_containers_running':True,'temporary_export_key_removed':True,'timer_active':True,'manual_scheduled_backup_result':'success','next_run':next_run,'private_permissions_verified':True}))
