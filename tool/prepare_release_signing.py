"""Create/reuse a private release key, retain a private local backup, publish only its certificate digest."""
import hashlib
import json
from pathlib import Path
import secrets
import shutil
import subprocess

root=Path(__file__).resolve().parents[1]
private=root/'.artifact-work/release-signing'
backup=Path.home()/'LineSight-private/release-signing-v1'
keytool=Path('C:/Program Files/Java/jdk-21/bin/keytool.exe')
assert subprocess.run(['git','check-ignore','-q','.artifact-work/release-signing/key.properties'],cwd=root).returncode==0
private.mkdir(parents=True,exist_ok=True)
password=private/'password.txt';keystore=private/'linesight-release.p12'
if keystore.exists() and not password.exists():
    raise RuntimeError('Existing release key has no local password file; restore private signing files before continuing.')
if not password.exists():
    with password.open('x',encoding='utf-8') as output:output.write(secrets.token_urlsafe(48)+'\n')
def run(*args):
    result=subprocess.run([str(keytool),*map(str,args)],cwd=root,capture_output=True)
    if result.returncode:
        raise RuntimeError('Private signing operation failed; existing keys were preserved.')
if not keystore.exists():
    run('-genkeypair','-keystore',keystore,'-storetype','PKCS12','-alias','linesight-release',
        '-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=LineSight Release, O=LineSight, C=CN',
        '-storepass:file',password,'-keypass:file',password)
run('-list','-keystore',keystore,'-alias','linesight-release','-storepass:file',password)
certificate=private/'release-certificate.der'
run('-exportcert','-keystore',keystore,'-alias','linesight-release','-storepass:file',password,'-file',certificate)
secret=password.read_text(encoding='utf-8').strip()
properties=f'storeFile={keystore.as_posix()}\nstorePassword={secret}\nkeyAlias=linesight-release\nkeyPassword={secret}\n'
property_file=private/'key.properties'
if property_file.exists() and property_file.read_text(encoding='utf-8')!=properties:
    raise RuntimeError('Signing properties differ from the existing release key; no files were overwritten.')
if not property_file.exists():property_file.write_text(properties,encoding='utf-8')
backup.mkdir(parents=True,exist_ok=True)
for name in ['password.txt','linesight-release.p12','key.properties','release-certificate.der']:
    source=private/name;destination=backup/name
    if destination.exists():
        assert destination.read_bytes()==source.read_bytes(),'Existing signing backup differs; preserved both keys.'
    else:shutil.copy2(source,destination)
digest=hashlib.sha256(certificate.read_bytes()).hexdigest()
public=root/'docs/product/linesight/acceptance/release-batch';public.mkdir(parents=True,exist_ok=True)
(public/'release-certificate.json').write_text(json.dumps({'certificate_sha256':digest,'key_algorithm':'RSA-3072','alias':'linesight-release',
    'debug_certificate':False,'private_key_in_repository':False,'private_backup':'Local user-profile backup; off-host backup remains pending',
    'existing_debug_install_can_upgrade_to_this_certificate':False},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'release_certificate_sha256':digest,'private_key_reused_or_created':True,'private_local_backup_verified':True,'secrets_printed':False}))
