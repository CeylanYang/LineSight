"""Use Caddy's packaged filter encoder; verify with an isolated failed upstream."""
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import uuid


FILTER = '''log default {
    format filter {
        wrap json
        fields {
            request delete
            headers delete
            uri delete
            url delete
            error delete
            msg delete
        }
    }
}'''
CADDY = '/usr/local/bin/caddy'


def main():
    assert os.geteuid()==0
    canary='PRIVATE-PROXY-'+uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix='linesight-proxy-log-') as folder:
        folder=Path(folder)
        isolated=folder/'Caddyfile'
        isolated.write_text('{\nadmin off\nauto_https off\n'+FILTER+'\n}\n'
            'http://127.0.0.1:18098 {\nreverse_proxy 127.0.0.1:18099\n}\n')
        output=folder/'stderr'
        with output.open('wb') as logs:
            process=subprocess.Popen([CADDY,'run','--config',str(isolated),'--adapter','caddyfile'],
                stdout=logs,stderr=logs)
            try:
                for attempt in range(30):
                    assert process.poll() is None,'Isolated Caddy stopped'
                    try:
                        urlopen(Request('http://127.0.0.1:18098/'+canary+'?code='+canary,
                            headers={'Authorization':'Bearer '+canary,'Cookie':'session='+canary}),timeout=2)
                    except HTTPError as error:
                        assert error.code==502;break
                    except URLError:time.sleep(.1)
                else:raise RuntimeError('Isolated proxy did not become ready')
            finally:
                process.terminate();process.wait(timeout=10)
        raw=output.read_text()
        assert canary not in raw,'Proxy canary leaked'
        records=[]
        for line in raw.splitlines():
            try:records.append(json.loads(line))
            except ValueError:pass
        errors=[r for r in records if r.get('logger')=='http.log.error' and r.get('status')==502]
        assert errors and all('request' not in r for r in errors)
        path=Path('/etc/caddy/Caddyfile');before=path.read_bytes()
        source=before.decode()
        assert source.startswith('{\n') and 'log default {' not in source
        candidate=source.replace('{\n','{\n'+FILTER+'\n',1)
        staged=folder/'production.Caddyfile';staged.write_text(candidate)
        subprocess.run([CADDY,'validate','--config',str(staged),'--adapter','caddyfile'],check=True,capture_output=True)
        backup=Path('/var/backups/linesight/private-logs')/dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        backup.mkdir(parents=True,mode=0o700)
        shutil.copy2(path,backup/'Caddyfile')
        try:
            assert path.read_bytes()==before,'Concurrent proxy change'
            path.write_text(candidate)
            subprocess.run(['systemctl','reload','caddy'],check=True,capture_output=True)
            for url in ['https://47.111.81.94/','https://99ai.pronhubcn.com/linesight/']:
                with urlopen(url,timeout=15) as response:assert response.status==200
        except BaseException:
            path.write_bytes(before)
            subprocess.run(['systemctl','reload','caddy'],check=True,capture_output=True)
            raise
    print(json.dumps({'official_caddy_filter_encoder':True,'isolated_upstream_failure_status':502,
        'url_query_authorization_cookie_canary_absent':True,'error_status_and_location_retained':True,
        'public_api_and_portal_https':200,'backup':str(backup),'test_proxy_stopped':True}))


if __name__=='__main__':main()
