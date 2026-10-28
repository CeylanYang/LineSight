set -eu
mkdir -p /opt/linesight-extras/node /opt/linesight-extras/whatif-8085
tar -xzf /tmp/node-linux.tgz -C /opt/linesight-extras/node --strip-components=1
tar -xzf /tmp/whatif-site.tar.gz -C /opt/linesight-extras/whatif-8085
chmod -R a+rX /opt/linesight-extras
cat > /etc/systemd/system/linesight-whatif.service <<'EOF'
[Unit]
Description=LineSight WhatIfIBought sample calculator
After=network.target
[Service]
Type=simple
DynamicUser=yes
WorkingDirectory=/opt/linesight-extras/whatif-8085/site
ExecStart=/opt/linesight-extras/node/bin/node server.js
Environment=NODE_ENV=production
Environment=HOSTNAME=127.0.0.1
Environment=PORT=3008
Environment=NODE_OPTIONS=--max-old-space-size=160
Environment=NEXT_TELEMETRY_DISABLED=1
MemoryMax=320M
CPUQuota=25%
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now linesight-whatif
python3 - <<'PY'
from pathlib import Path
import shutil,time
p=Path('/etc/caddy/Caddyfile');s=p.read_text()
if 'handle /linesight/whatif*' not in s:
 shutil.copy2(p,str(p)+'.before-whatif-'+str(int(time.time())))
 block='''    handle /linesight/whatif* {
        request_body {
            max_size 64KB
        }
        @internal path /linesight/whatif/api-setup* /linesight/whatif/api-test*
        respond @internal 404
        reverse_proxy 127.0.0.1:3008
    }
'''
 s=s.replace('99ai.pronhubcn.com {\n','99ai.pronhubcn.com {\n'+block,1)
 p.write_text(s)
PY
/usr/local/bin/caddy validate --config /etc/caddy/Caddyfile >/tmp/linesight-whatif-caddy-check.log 2>&1
systemctl reload caddy
sleep 2
systemctl is-active linesight-whatif
curl -s -o /tmp/whatif-response.html -w '%{http_code}\n' http://127.0.0.1:3008/linesight/whatif
