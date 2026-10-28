"""Provision isolated WIIB data stores and a Keycloak audience; never reset users.

Run on the LineSight host with its deployment Python. Secrets stay in root-only
files and must be backed up to the operator's private vault before cutover.
"""
from pathlib import Path
import argparse
import base64
import json
import os
import secrets
import subprocess
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--sso-only', action='store_true')
args = parser.parse_args()

ROOT = Path('/opt/linesight-extras/wtfibought-144')
PRIVATE = Path('/etc/linesight/wiib.env')
BACKUP = Path('/var/backups/linesight/wtf144')
BACKUP.mkdir(parents=True, exist_ok=True, mode=0o700)


def read_env(path):
    return dict(line.split('=', 1) for line in Path(path).read_text().splitlines()
                if line and not line.startswith('#') and '=' in line)


def kc(method, path, payload=None):
    request = urllib.request.Request(
        'http://127.0.0.1:8081/sso/admin/' + path,
        data=None if payload is None else json.dumps(payload).encode(),
        headers={'Authorization': 'Bearer ' + admin_token,
                 'Content-Type': 'application/json'}, method=method)
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read()
        return json.loads(data) if data else None


identity = read_env('/opt/linesight-identity/identity.env')
credentials = urllib.parse.urlencode({
    'client_id': 'admin-cli', 'grant_type': 'password',
    'username': identity['KEYCLOAK_ADMIN_USERNAME'],
    'password': identity['KEYCLOAK_ADMIN_PASSWORD'],
}).encode()
with urllib.request.urlopen(urllib.request.Request(
        'http://127.0.0.1:8081/sso/realms/master/protocol/openid-connect/token',
        data=credentials), timeout=30) as response:
    admin_token = json.load(response)['access_token']
realm = kc('GET', 'realms/linesight')
assert not realm.get('registrationAllowed'), 'Realm registration must remain closed'
admin_users = kc('GET', 'realms/linesight/users?username=lsuser01&exact=true')
assert len(admin_users) == 1 and admin_users[0]['enabled']
clients = kc('GET', 'realms/linesight/clients?clientId=linesight-whatif')
assert len(clients) == 1
client_path = 'realms/linesight/clients/' + clients[0]['id']
client = kc('GET', client_path)
assert not client.get('directAccessGrantsEnabled'), 'Password grant must stay closed'
backup = BACKUP / 'keycloak-client-before.json'
if not backup.exists():
    backup.write_text(json.dumps(client, ensure_ascii=False, indent=2))
    backup.chmod(0o600)
# Keycloak 26 moves access-token `sub` into its standard `basic` client scope.
# The historical gateway client explicitly listed only profile/email; retaining
# those alone gives a valid signed token without a stable subject. Use Keycloak's
# stock mapper rather than linking WIIB profiles by mutable username.
scopes = kc('GET', 'realms/linesight/client-scopes')
basic = [scope for scope in scopes if scope['name'] == 'basic']
assert len(basic) == 1, 'Keycloak standard basic scope is required'
kc('PUT', client_path + '/default-client-scopes/' + basic[0]['id'])
mapper = {'name': 'wiib-api-audience', 'protocol': 'openid-connect',
          'protocolMapper': 'oidc-audience-mapper', 'consentRequired': False,
          'config': {'included.custom.audience': 'wiib',
                     'access.token.claim': 'true', 'id.token.claim': 'false',
                     'introspection.token.claim': 'true'}}
existing = [m for m in client.get('protocolMappers', [])
            if m['name'] == mapper['name']]
if not existing:
    kc('POST', client_path + '/protocol-mappers/models', mapper)
else:
    mapper['id'] = existing[0]['id']
    kc('PUT', client_path + '/protocol-mappers/models/' + mapper['id'], mapper)
if args.sso_only:
    print(json.dumps({'basic_scope': True, 'audience': 'wiib', 'passwords_reset': False}))
    raise SystemExit(0)

container = 'linesight-identity_postgres_1'
inspect = json.loads(subprocess.check_output(['podman', 'inspect', container]))[0]
pg_env = dict(item.split('=', 1) for item in inspect['Config']['Env'] if '=' in item)
pg_admin = pg_env['POSTGRES_USER']
networks = inspect['NetworkSettings']['Networks']
pg_host = next(n['IPAddress'] for n in networks.values() if n.get('IPAddress'))

if not PRIVATE.exists():
    values = {
        'PG_HOST': pg_host, 'PG_PORT': '5432', 'PG_DB': 'wiib', 'PG_USER': 'wiib',
        'PG_PASSWORD': secrets.token_hex(32),
        'REDIS_HOST': '127.0.0.1', 'REDIS_PORT': '16379', 'REDIS_DB': '0',
        'REDIS_PASSWORD': secrets.token_hex(32),
        'INTERNAL_API_TOKEN': secrets.token_hex(32),
        'WIIB_TRADER_KEY_SECRET': base64.b64encode(secrets.token_bytes(32)).decode(),
        'TRADE_ALIAS_SALT': secrets.token_hex(32),
        'LINESIGHT_WIIB_ADMIN_SUBJECT': admin_users[0]['id'],
        'PASSWORD_LOGIN_ENABLED': 'false', 'FEED_INTERNAL_BASE_URL': 'http://127.0.0.1:18081',
        'SIM_INTERNAL_BASE_URL': 'http://127.0.0.1:18080',
        'BINANCE_REST_BASE_URL': 'https://data-api.binance.vision',
        'BINANCE_WS_URL': 'wss://data-stream.binance.vision/ws',
        'SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE': '3',
        'SPRING_DATASOURCE_HIKARI_MINIMUM_IDLE': '1',
        'WHALE_ENABLED': 'false', 'TZ': 'Asia/Shanghai',
    }
    fd = os.open(PRIVATE, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        output.write(''.join(k + '=' + v + '\n' for k, v in values.items()))
values = read_env(PRIVATE)
assert values['LINESIGHT_WIIB_ADMIN_SUBJECT'] == admin_users[0]['id']
assert values['PG_HOST'] == pg_host, 'Postgres network changed; update private PG_HOST before starting'


def sql(statement, database='postgres'):
    result = subprocess.run(['podman', 'exec', '-i', container, 'psql', '-X',
                             '-U', pg_admin, '-d', database,
                             '-v', 'ON_ERROR_STOP=1', '-tA'],
                            input=statement.encode(), capture_output=True)
    if result.returncode:
        raise RuntimeError('Isolated WIIB PostgreSQL provisioning failed; inspect privately')
    return result.stdout.decode().strip()


assert values['PG_PASSWORD'].isalnum()
if sql("SELECT count(*) FROM pg_roles WHERE rolname='wiib'") == '0':
    sql("CREATE ROLE wiib LOGIN PASSWORD '" + values['PG_PASSWORD'] + "'")
if sql("SELECT count(*) FROM pg_database WHERE datname='wiib'") == '0':
    sql('CREATE DATABASE wiib OWNER wiib')
if sql("SELECT to_regclass('public.user') IS NOT NULL", 'wiib') == 'f':
    for name in ['init.sql', 'bstock.sql']:
        sql('SET ROLE wiib;\n' + (ROOT / 'source/sql' / name).read_text(), 'wiib')
sql("SELECT setval(pg_get_serial_sequence('\"user\"','id'), "
    "GREATEST(100, (SELECT COALESCE(MAX(id),0)+1 FROM \"user\"), "
    "(SELECT last_value + CASE WHEN is_called THEN 1 ELSE 0 END FROM user_id_seq)), false)", 'wiib')
table_count = sql("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'", 'wiib')

subprocess.run(['useradd', '--system', '--home-dir', '/var/lib/linesight-wiib',
                '--shell', '/sbin/nologin', 'linesight-wiib'], capture_output=True)
data = Path('/var/lib/linesight-wiib')
data.mkdir(exist_ok=True, mode=0o750)
subprocess.run(['chown', 'linesight-wiib:linesight-wiib', str(data)], check=True)
redis_dir = data / 'redis'
redis_dir.mkdir(exist_ok=True, mode=0o750)
subprocess.run(['chown', 'linesight-wiib:linesight-wiib', str(redis_dir)], check=True)
redis_conf = data / 'redis.conf'
redis_text = ('bind 127.0.0.1\nport 16379\nprotected-mode yes\n'
                      'daemonize no\nlogfile ""\ndir /var/lib/linesight-wiib/redis\n'
                      'appendonly yes\nmaxmemory 64mb\nmaxmemory-policy noeviction\n'
                      'requirepass ' + values['REDIS_PASSWORD'] + '\n')
redis_changed = not redis_conf.exists() or redis_conf.read_text() != redis_text
redis_conf.write_text(redis_text)
redis_conf.chmod(0o640)
subprocess.run(['chown', 'root:linesight-wiib', str(redis_conf)], check=True)
Path('/etc/systemd/system/linesight-wiib-redis.service').write_text('''[Unit]
Description=WIIB isolated Redis
After=network.target
[Service]
User=linesight-wiib
Group=linesight-wiib
ExecStart=/usr/bin/redis-server /var/lib/linesight-wiib/redis.conf
Restart=on-failure
RestartSec=5
MemoryMax=112M
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/lib/linesight-wiib/redis
[Install]
WantedBy=multi-user.target
''')
subprocess.run(['systemctl', 'daemon-reload'], check=True)
was_active = subprocess.run(['systemctl', 'is-active', '--quiet', 'linesight-wiib-redis']).returncode == 0
subprocess.run(['systemctl', 'enable', '--now', 'linesight-wiib-redis'], check=True,
               stdout=subprocess.DEVNULL)
if redis_changed and was_active:
    subprocess.run(['systemctl', 'restart', 'linesight-wiib-redis'], check=True)
import time
time.sleep(1)
redis_env = os.environ.copy()
redis_env['REDISCLI_AUTH'] = values['REDIS_PASSWORD']
ping = subprocess.run(['redis-cli', '-h', '127.0.0.1', '-p', '16379', 'PING'],
                      env=redis_env, capture_output=True)
assert ping.returncode == 0 and ping.stdout.strip() == b'PONG', 'Isolated Redis is not ready'
assert sql('SELECT count(*) FROM "user" WHERE password_hash IS NOT NULL', 'wiib') == '0'
print(json.dumps({'database': 'wiib', 'tables': int(table_count),
                  'realm_registration': False, 'audience': 'wiib',
                  'passwords_reset': False, 'redis': '127.0.0.1:16379'}))
