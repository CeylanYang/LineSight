"""Root-only Postfix 465 cutover. Read private configuration from SSH stdin."""
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import smtplib
import ssl
import subprocess
import sys


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def main():
    assert os.geteuid() == 0
    v = json.load(sys.stdin)
    assert v['host'] == 'smtp.163.com' and int(v['port']) == 465
    assert v['sender'] == v['username'] == 'kkk456miao@163.com'
    secret = v['authorization_code'].strip()
    assert secret and not any(c in secret for c in '\r\n\x00')
    with smtplib.SMTP_SSL(v['host'], 465, context=ssl.create_default_context(), timeout=25) as smtp:
        smtp.login(v['username'], secret)
    assert not run('postqueue', '-j').stdout.strip(), 'Queue must be empty before cutover'
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path('/var/backups/linesight/mail') / ('relay-' + stamp)
    backup.mkdir(mode=0o700, parents=True)
    files = ['/etc/postfix/main.cf', '/etc/postfix/sasl_passwd',
             '/etc/postfix/sasl_passwd.db', '/etc/postfix/linesight_transport',
             '/etc/postfix/linesight_transport.db', '/etc/postfix/master.cf']
    for name in files:
        p = Path(name)
        if p.exists():
            assert p.is_file() and not p.is_symlink()
            shutil.copy2(p, backup / p.name)
            (backup / p.name).chmod(0o600)
    os.umask(0o077)
    try:
        Path(files[1]).write_text('[smtp.163.com]:465 ' + v['username'] + ':' + secret + '\n')
        Path(files[1]).chmod(0o600)
        # Keep all disposable .invalid reset tests inside the private Mailpit sink.
        Path(files[3]).write_text('example.invalid mailpit:[10.89.0.1]:1025\n')
        master=Path('/etc/postfix/master.cf')
        content=master.read_text()
        if '\nmailpit ' not in content:
            master.write_text(content+'\nmailpit unix - - n - - smtp\n'
                '  -o smtp_tls_wrappermode=no\n  -o smtp_tls_security_level=none\n'
                '  -o smtp_sasl_auth_enable=no\n')
        run('postmap', files[1]); run('postmap', files[3])
        config = {
            'relayhost': '[smtp.163.com]:465', 'smtp_tls_wrappermode': 'yes',
            'smtp_tls_security_level': 'verify',
            'smtp_tls_CAfile': '/etc/pki/tls/certs/ca-bundle.crt',
            'smtp_sasl_auth_enable': 'yes',
            'smtp_sasl_password_maps': 'hash:/etc/postfix/sasl_passwd',
            'smtp_sasl_security_options': 'noanonymous',
            'smtp_sasl_tls_security_options': 'noanonymous',
            'transport_maps': 'hash:/etc/postfix/linesight_transport',
        }
        for key, value in config.items():
            run('postconf', '-e', key + ' = ' + value)
        run('postfix', 'check'); run('systemctl', 'reload', 'postfix')
    except BaseException:
        for name in files:
            saved = backup / Path(name).name
            if saved.exists(): shutil.copy2(saved, name)
            else: Path(name).unlink(missing_ok=True)
        run('systemctl', 'reload', 'postfix')
        raise
    report = {'relay': 'smtp.163.com:465', 'tls_certificate_verification': True,
              'smtp_auth_verified': True, 'sender': v['sender'],
              'private_test_domain_retained': True, 'backup': str(backup),
              'public_smtp_enabled': False}
    Path('/etc/linesight-smtp-relay.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    try: main()
    except Exception as error:
        print(json.dumps({'passed': False, 'error_type': type(error).__name__}))
        raise SystemExit(1)
