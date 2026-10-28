"""Install original WIIB JVM services without touching the production web route."""
from pathlib import Path
import json
import subprocess
import time
import urllib.request

ROOT = Path('/opt/linesight-extras/wtfibought-144')
JDK = next(Path('/opt/linesight-extras/wtf144-tools').glob('jdk-25*/bin/java'))
for module, port, heap, meta, limit in [
        ('feed', 18081, 96, 128, 320),
        ('sim', 18080, 144, 144, 400),
        ('agent', 18082, 160, 192, 480)]:
    jar = ROOT / f'source/wiib-{module}/target/wiib-{module}-0.0.1-SNAPSHOT.jar'
    assert jar.is_file(), f'Build missing for {module}'
    unit = f'''[Unit]
Description=What If I Bought original {module}
After=network-online.target linesight-identity.service linesight-wiib-redis.service
Requires=linesight-wiib-redis.service
[Service]
User=linesight-wiib
Group=linesight-wiib
WorkingDirectory={ROOT}
EnvironmentFile=/etc/linesight/wiib.env
Environment=SERVER_ADDRESS=127.0.0.1 SERVER_PORT={port}
ExecStart={JDK} -Xms32m -Xmx{heap}m -XX:MaxMetaspaceSize={meta}m -XX:ActiveProcessorCount=1 -XX:ReservedCodeCacheSize=48m -Xss512k -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError -jar {jar}
Restart=on-failure
RestartSec=10
TimeoutStartSec=180
TimeoutStopSec=30
MemoryMax={limit}M
CPUQuota=80%
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/linesight-wiib
[Install]
WantedBy=multi-user.target
'''
    Path(f'/etc/systemd/system/linesight-wiib-{module}.service').write_text(unit)
subprocess.run(['systemctl', 'daemon-reload'], check=True)
for module, port in [('feed', 18081), ('sim', 18080), ('agent', 18082)]:
    subprocess.run(['systemctl', 'enable', '--now', f'linesight-wiib-{module}'],
                   check=True, stdout=subprocess.DEVNULL)
    ready = False
    for attempt in range(90):
        try:
            with urllib.request.urlopen(f'http://127.0.0.1:{port}/actuator/health', timeout=3) as response:
                health = json.load(response)
            # Upstream intentionally requires a native session for sim/agent
            # Actuator. A 401 here means the application is accepting requests;
            # authenticated dependency health is verified before public cutover.
            if health.get('status') == 'UP' or health.get('code') == 401:
                ready = True
                break
        except Exception:
            pass
        time.sleep(2)
    print(json.dumps({'service': module, 'servlet_ready': ready}), flush=True)
    if not ready:
        raise SystemExit(1)
