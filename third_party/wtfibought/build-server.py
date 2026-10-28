from pathlib import Path
import json,urllib.request,hashlib,tarfile,zipfile,subprocess,os
stage=Path('/var/tmp/linesight-wtf144');tools=Path('/opt/linesight-extras/wtf144-tools');tools.mkdir(parents=True,exist_ok=True)
info=json.loads((stage/'linux-jdk.json').read_text())
archive=tools/'jdk25.tar.gz'
if not archive.exists():
 with urllib.request.urlopen(info['url'],timeout=60)as r,archive.open('wb')as w:
  while chunk:=r.read(1024*1024):w.write(chunk)
assert hashlib.sha256(archive.read_bytes()).hexdigest()==info['digest'],'JDK SHA256 mismatch'
with tarfile.open(archive)as tar:
 base=tools.resolve();assert all((base/p.name).resolve().is_relative_to(base) for p in tar.getmembers())
 tar.extractall(tools,filter='data')
jdk=next(p for p in tools.glob('jdk-25*')if p.is_dir())
maven=tools/'maven.tar.gz';url='https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.tar.gz'
if not maven.exists():
 with urllib.request.urlopen(url,timeout=60)as r,maven.open('wb')as w:w.write(r.read())
with urllib.request.urlopen(url+'.sha512',timeout=30)as r:expected=r.read().decode().strip().split()[0]
assert hashlib.sha512(maven.read_bytes()).hexdigest()==expected
with tarfile.open(maven)as tar:
 base=tools.resolve();assert all((base/p.name).resolve().is_relative_to(base) for p in tar.getmembers())
 tar.extractall(tools,filter='data')
source=Path('/opt/linesight-extras/wtfibought-144/source');source.mkdir(parents=True,exist_ok=True)
with tarfile.open(stage/'source.tar.gz')as tar:
 base=source.resolve();assert all((base/p.name).resolve().is_relative_to(base)for p in tar.getmembers());tar.extractall(source,filter='data')
env=os.environ.copy();env['JAVA_HOME']=str(jdk);env['PATH']=str(jdk/'bin')+':'+env['PATH'];env['MAVEN_OPTS']='-Xms32m -Xmx256m -XX:MaxMetaspaceSize=160m -XX:ActiveProcessorCount=1'
settings=stage/'settings.xml';settings.write_text('<settings><mirrors><mirror><id>verified-central</id><mirrorOf>*</mirrorOf><url>https://repo.maven.apache.org/maven2</url></mirror></mirrors></settings>')
print('Toolchain digests verified; building official feed/sim/agent modules.',flush=True)
with (stage/'maven-build.log').open('w')as log:
 result=subprocess.run([str(tools/'apache-maven-3.9.16/bin/mvn'),'-s',str(settings),'-B','-ntp','package','-pl','wiib-feed,wiib-agent,wiib-sim','-am','-DskipTests'],cwd=source,env=env,stdout=log,stderr=subprocess.STDOUT)
print('Maven build exit:',result.returncode,flush=True)
if result.returncode:
 print('\n'.join((stage/'maven-build.log').read_text().splitlines()[-35:]))
 raise SystemExit(result.returncode)
print(json.dumps({'jdk':str(jdk),'jdk_sha256':info['digest'],'source':str(source),'artifacts':[str(p)for p in source.glob('*/target/*.jar')]}))
