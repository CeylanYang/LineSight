"""Configure packaged Postfix/OpenDKIM with private listeners and Mailpit staging.

Run as root on the LineSight host. External delivery is deliberately a separate
cutover after DNS, port 25 and recipient acceptance have been verified.
"""
import datetime as dt
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess

DOMAIN = '99ai.pronhubcn.com'
SELECTOR = 'linesight2026'


def main():
    if os.geteuid() != 0:
        raise RuntimeError('Run as root on the deployment host')
    if Path('/etc/linesight-postfix-stage.json').exists():
        raise RuntimeError('Mail already staged; inspect before changing existing deployment')
    backup = Path('/var/backups/linesight/mail') / dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup.mkdir(mode=0o700, parents=True)
    originals = ['/etc/postfix/main.cf','/etc/postfix/master.cf','/etc/opendkim.conf']
    for path in originals:
        shutil.copy2(path, backup/Path(path).name)
    keys = Path('/etc/opendkim/keys')/DOMAIN
    keys.mkdir(mode=0o700, parents=True, exist_ok=True)
    private = keys/(SELECTOR+'.private')
    if not private.exists():
        subprocess.run(['opendkim-genkey','-b','2048','-d',DOMAIN,'-s',SELECTOR,'-D',str(keys)],check=True)
    owner = pwd.getpwnam('opendkim')
    os.chown(keys,owner.pw_uid,owner.pw_gid)
    for path in keys.iterdir():
        os.chown(path,owner.pw_uid,owner.pw_gid);path.chmod(0o600)
    Path('/etc/opendkim.conf').write_text(
        'Mode s\nSyslog yes\nSyslogSuccess yes\nLogWhy no\nUserID opendkim:opendkim\n'
        'Socket inet:8891@127.0.0.1\nUmask 007\nCanonicalization relaxed/relaxed\n'
        f'Domain {DOMAIN}\nSelector {SELECTOR}\nKeyFile {private}\n'
        'InternalHosts 127.0.0.1,10.89.0.4\nOversignHeaders From\nSendReports no\n')
    config = {
        'myhostname':'mail.'+DOMAIN,'mydomain':DOMAIN,'myorigin':DOMAIN,
        'inet_interfaces':'127.0.0.1, 10.89.0.1','inet_protocols':'ipv4',
        'mynetworks':'127.0.0.0/8, 10.89.0.4/32',
        'mydestination':'localhost, localhost.localdomain',
        'smtpd_relay_restrictions':'permit_mynetworks,reject_unauth_destination',
        'smtpd_recipient_restrictions':'permit_mynetworks,reject',
        'relayhost':'[10.89.0.1]:1025',
        'smtpd_milters':'inet:127.0.0.1:8891','non_smtpd_milters':'inet:127.0.0.1:8891',
        'milter_default_action':'tempfail','milter_protocol':'6',
        'smtp_tls_security_level':'may','message_size_limit':'1048576',
        'smtpd_banner':'$myhostname ESMTP','disable_vrfy_command':'yes'}
    for key,value in config.items():
        subprocess.run(['postconf','-e',key+' = '+value],check=True)
    master=Path('/etc/postfix/master.cf')
    text=master.read_text()
    text,count=re.subn(r'^smtp\s+inet\s+.*$', '# LineSight: public SMTP listener disabled',text,flags=re.M)
    if count != 1:
        raise RuntimeError('Unexpected master.cf; inspect before enabling service')
    master.write_text(text+'\n127.0.0.1:2525 inet n - n - - smtpd\n10.89.0.1:2525 inet n - n - - smtpd\n')
    try:
        subprocess.run(['opendkim','-n','-x','/etc/opendkim.conf'],check=True,capture_output=True)
        subprocess.run(['postfix','check'],check=True,capture_output=True)
        subprocess.run(['systemctl','enable','--now','opendkim','postfix'],check=True,capture_output=True)
    except BaseException:
        subprocess.run(['systemctl','stop','postfix','opendkim'],check=True)
        for path in originals:shutil.copy2(backup/Path(path).name,path)
        raise
    public = (keys/(SELECTOR+'.txt')).read_text()
    txt=''.join(re.findall(r'"([^"]*)"',public))
    records=[
        {'type':'TXT','name':'@','value':'v=spf1 ip4:47.111.81.94 -all','ttl':300},
        {'type':'TXT','name':SELECTOR+'._domainkey','value':txt,'ttl':300},
        {'type':'TXT','name':'_dmarc','value':'v=DMARC1; p=none; adkim=s; aspf=s','ttl':300}]
    report={'domain':DOMAIN,'software':['Postfix','OpenDKIM'],
        'smtp_listeners':['127.0.0.1:2525','10.89.0.1:2525'],
        'private_signing_key_in_report':False,'mode':'Mailpit staging relay; external delivery disabled',
        'dns_records':records,'backup':str(backup)}
    Path('/etc/linesight-postfix-stage.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))


if __name__=='__main__':main()
