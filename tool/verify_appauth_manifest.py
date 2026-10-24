"""Reject Android task separation that strands the native OIDC callback."""
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
android='{http://schemas.android.com/apk/res/android}'

def verify(path,merged=False):
    manifest=ET.parse(path).getroot()
    application=manifest.find('application')
    activities={a.get(android+'name'):a for a in application.findall('activity')}
    main=next(a for name,a in activities.items() if name.endswith('.MainActivity'))
    default=application.get(android+'taskAffinity',manifest.get('package','com.example.linesight_flutter'))
    affinity=main.get(android+'taskAffinity',default)
    assert affinity, 'MainActivity must share the AppAuth task; empty taskAffinity strands browser callbacks'
    assert main.get(android+'launchMode')=='singleTop'
    if merged:
        management=activities['net.openid.appauth.AuthorizationManagementActivity']
        receiver=activities['net.openid.appauth.RedirectUriReceiverActivity']
        assert management.get(android+'taskAffinity',default)==affinity, 'AppAuth task differs from Flutter task'
        assert management.get(android+'launchMode')=='singleTask'
        assert receiver.get(android+'exported')=='true'
        schemes={d.get(android+'scheme') for d in receiver.findall('intent-filter/data')}
        assert 'com.linesight.app' in schemes, 'Registered OIDC callback receiver missing'
        assert all(d.get(android+'scheme')!='com.linesight.app' for d in main.findall('intent-filter/data')), 'Flutter task links must not consume OIDC callbacks'
    return {'path':str(path.relative_to(root)),'shared_task_affinity':affinity,'callback_receiver_verified':merged}

reports=[verify(root/'android/app/src/main/AndroidManifest.xml')]
if '--merged' in sys.argv:
    reports.append(verify(root/'build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml',True))
print(json.dumps(reports))
