"""Compile a small SPI extension against the exact deployed Keycloak release, no VM."""
from pathlib import Path
import os
import subprocess
from urllib.request import urlopen

root=Path(__file__).resolve().parents[1]
work=root/'.artifact-work/nfc-provider';work.mkdir(parents=True,exist_ok=True)
artifacts=[('org/keycloak',name,'26.8.1') for name in ['keycloak-core','keycloak-server-spi','keycloak-server-spi-private','keycloak-services']]
artifacts += [('jakarta/ws/rs','jakarta.ws.rs-api','3.1.0'),('org/jboss/logging','jboss-logging','3.6.1.Final')]
jars=[]
for group,name,version in artifacts:
    target=work/f'{name}-{version}.jar';jars.append(str(target))
    if not target.exists():
        with urlopen(f'https://repo.maven.apache.org/maven2/{group}/{name}/{version}/{target.name}',timeout=60) as response:
            target.write_bytes(response.read())
classes=work/'classes';classes.mkdir(exist_ok=True)
java=Path('C:/Program Files/Java/jdk-21/bin')
subprocess.run([str(java/'javac.exe'),'-encoding','UTF-8','--release','21','-cp',os.pathsep.join(jars),'-d',str(classes),str(root/'deploy/nfc/src/com/linesight/identity/NfcTicketAuthenticator.java')],check=True)
subprocess.run([str(java/'jar.exe'),'cf',str(work/'linesight-nfc-provider.jar'),'-C',str(classes),'.','-C',str(root/'deploy/nfc'),'META-INF'],check=True)
print('Keycloak NFC provider compiled against 26.8.1')
