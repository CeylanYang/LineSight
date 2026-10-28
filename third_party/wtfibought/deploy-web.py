"""Stage the original SPA; switch only the existing stock gateway upstream.

The live Caddyfile is backed up and changed additively. Existing LineSight,
identity, OTA and mail routes are deliberately read from the host, never from a
stale copy in this checkout.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess
import tarfile
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--cutover', action='store_true')
args = parser.parse_args()
ROOT = Path('/opt/linesight-extras/wtfibought-144')
STAGE = Path('/var/tmp/linesight-wtf144')
BACKUP = Path('/var/backups/linesight/wtf144')
WEB = ROOT / 'web'
WEB.mkdir(exist_ok=True)
with tarfile.open(STAGE / 'web.tar.gz') as archive:
    assert all((WEB / item.name).resolve().is_relative_to(WEB) for item in archive.getmembers())
    archive.extractall(WEB, filter='data')
index = (WEB / 'index.html').read_text()
assert 'WIIB' not in index or '/linesight/whatif/assets/' in index
assert '/linesight/whatif/logo.png' in index

config = Path('/etc/caddy/Caddyfile')
current = config.read_text()
begin = '# BEGIN WIIB ORIGINAL 144'
block = '''
# BEGIN WIIB ORIGINAL 144
http://:3009 {
    bind 127.0.0.1
    route {
        redir /linesight/whatif /linesight/whatif/ 308
        handle /linesight/whatif/alpha* {
            respond "服务暂未开放" 503
        }
        handle /linesight/whatif/api/alpha* {
            respond "服务暂未开放" 503
        }
        @agent path /linesight/whatif/api/ai* /linesight/whatif/api/testnet* /linesight/whatif/api/admin/ai-agent*
        handle @agent {
            uri strip_prefix /linesight/whatif
            reverse_proxy 127.0.0.1:18082 {
                flush_interval -1
            }
        }
        handle /linesight/whatif/api/* {
            uri strip_prefix /linesight/whatif
            reverse_proxy 127.0.0.1:18080
        }
        handle /linesight/whatif/ws/* {
            uri strip_prefix /linesight/whatif
            reverse_proxy 127.0.0.1:18080
        }
        handle_path /linesight/whatif/* {
            root * /opt/linesight-extras/wtfibought-144/web
            try_files {path} /index.html
            file_server
        }
        respond 404
    }
}
# END WIIB ORIGINAL 144
'''
if begin not in current:
    assert hashlib.sha256(config.read_bytes()).hexdigest() == '80856bb1c0cad8f804c27e15a312d61090f3f0dbb25403beb17500c2e47f1634', 'Live Caddy changed; review before editing'
    BACKUP.mkdir(exist_ok=True, parents=True, mode=0o700)
    shutil.copy2(config, BACKUP / 'Caddyfile.before')
    candidate = STAGE / 'Caddyfile.candidate'
    candidate.write_text(current + block)
    subprocess.run(['caddy', 'validate', '--config', str(candidate), '--adapter', 'caddyfile'], check=True)
    config.write_text(current + block)
    subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
elif 'http://127.0.0.1:3009 {' in current:
    # OAuth2 Proxy intentionally preserves the public Host. Bind loopback but
    # accept that Host rather than matching only "127.0.0.1" in this server.
    fixed = current.replace('http://127.0.0.1:3009 {', 'http://:3009 {', 1)
    candidate = STAGE / 'Caddyfile.candidate'
    candidate.write_text(fixed)
    subprocess.run(['caddy', 'validate', '--config', str(candidate), '--adapter', 'caddyfile'], check=True)
    config.write_text(fixed)
    subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
with urllib.request.urlopen('http://127.0.0.1:3009/linesight/whatif/') as response:
    assert '/linesight/whatif/assets/' in response.read().decode()
print('Original SPA staged behind loopback only.', flush=True)

if args.cutover:
    gateway = Path('/opt/linesight-extras/oauth2-proxy-7.15.5/whatif-auth.cfg')
    original = gateway.read_text()
    if not (BACKUP / 'whatif-auth.cfg.before').exists():
        shutil.copy2(gateway, BACKUP / 'whatif-auth.cfg.before')
    new = original.replace('http://127.0.0.1:3008/', 'http://127.0.0.1:3009/').replace(
        'pass_access_token = false', 'pass_access_token = true')
    if 'backend_logout_url' not in new:
        new += '\nbackend_logout_url = "https://99ai.pronhubcn.com/sso/realms/linesight/protocol/openid-connect/logout?id_token_hint={id_token}"\n'
    assert 'http://127.0.0.1:3009/' in new and 'pass_access_token = true' in new
    try:
        gateway.write_text(new)
        subprocess.run(['systemctl', 'restart', 'linesight-whatif-auth'], check=True)
        import time
        time.sleep(2)
        subprocess.run(['systemctl', 'is-active', '--quiet', 'linesight-whatif-auth'], check=True)
    except Exception:
        gateway.write_text(original)
        subprocess.run(['systemctl', 'restart', 'linesight-whatif-auth'], check=True)
        raise
    receipt = {'upstream': 'mamawai/wtfibought',
               'commit': 'd99fd9bae3564a2630880a3a8f52fcd0dfee7bdb',
               'cutover_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'url': 'https://99ai.pronhubcn.com/linesight/whatif/',
               'gateway': 'Keycloak + OAuth2 Proxy', 'passwords_reset': False}
    (STAGE / 'cutover.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))
