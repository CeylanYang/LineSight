"""Map the existing public LineSight portal to its domain; preserve the IP site."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess


def main():
    if os.geteuid()!=0:raise RuntimeError('Run on deployment host as root')
    config=Path('/etc/caddy/Caddyfile');old=config.read_text()
    assert Path('/srv/boji-portal/index.html').is_file()
    begin='# BEGIN LINESIGHT MAIL DOMAIN';end='# END LINESIGHT MAIL DOMAIN'
    section='''# BEGIN LINESIGHT MAIL DOMAIN
99ai.pronhubcn.com {
    encode zstd gzip
    header {
        X-Content-Type-Options nosniff
        Referrer-Policy same-origin
    }
    respond /health "ready" 200
    redir /linesight /linesight/ 308
    handle_path /linesight/* {
        root * /srv/boji-portal
        header Cache-Control no-cache
        file_server
    }
    handle {
        root * /srv/boji-portal
        header Cache-Control no-cache
        file_server
    }
}
mail.99ai.pronhubcn.com {
    header X-Content-Type-Options nosniff
    respond /health "ready" 200
    respond "LineSight" 200
}
# END LINESIGHT MAIL DOMAIN'''
    updated,count=re.subn(re.escape(begin)+r'.*?'+re.escape(end),section,old,flags=re.S)
    assert count==1,'Domain section missing or ambiguous'
    backup=Path('/var/backups/linesight/mail')/('portal-'+dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ'))
    backup.mkdir(mode=0o700,parents=True);(backup/'Caddyfile').write_text(old)
    config.write_text(updated)
    try:
        subprocess.run([shutil.which('caddy'),'validate','--config',str(config)],check=True,capture_output=True)
        subprocess.run(['systemctl','reload','caddy'],check=True,capture_output=True)
    except BaseException:
        config.write_text(old);subprocess.run(['systemctl','reload','caddy'],check=True);raise
    print(json.dumps({'portal':'https://99ai.pronhubcn.com/',
        'legacy_path':'https://99ai.pronhubcn.com/linesight/',
        'existing_ip_site_preserved':True,'identity_issuer_changed':False,
        'portal_files_changed':False,'caddy_config_valid':True,'backup':str(backup)}))


if __name__=='__main__':main()
