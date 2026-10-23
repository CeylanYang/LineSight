"""Install the reviewed SSO route on the LineSight host, validating before reload."""
from datetime import datetime, timezone
from pathlib import Path
import os
import shutil
import subprocess

config = Path('/etc/caddy/Caddyfile')
original = config.read_text()
route = '\thandle /sso/* {\n\t\treverse_proxy 127.0.0.1:8081\n\t}\n'
if 'handle /sso/*' in original:
    print('SSO route already installed')
else:
    anchor = '\thandle_path /static/*'
    if original.count(anchor) != 1:
        raise SystemExit('Unexpected Caddy configuration; inspect before editing')
    changed = original.replace(anchor, route + anchor, 1)
    staged = config.with_name('Caddyfile.sso-staged')
    staged.write_text(changed)
    subprocess.run(['/usr/local/bin/caddy', 'validate', '--config', str(staged), '--adapter', 'caddyfile'], check=True)
    backups = Path('/var/backups/linesight/identity')
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups / ('Caddyfile-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    shutil.copy2(config, backup)
    os.replace(staged, config)
    try:
        subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
    except subprocess.CalledProcessError:
        shutil.copy2(backup, config)
        subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
        raise
    print('Validated SSO proxy installed; prior configuration backed up')
