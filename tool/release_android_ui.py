"""Small emulator-only blackbox UI helper; never installs or clears data."""
import argparse
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('action',choices=['inspect','tap','capture','back','swipe','launch'])
parser.add_argument('value',nargs='?')
parser.add_argument('--batch',default='release-batch')
parser.add_argument('--occurrence',type=int,default=0)
args=parser.parse_args()
if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*-batch',args.batch): parser.error('Use a simple acceptance batch directory name')
adb=[r'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe','-s','emulator-5554']
def run(*parts): return subprocess.check_output(adb+list(parts),timeout=45)
assert run('shell','getprop','ro.kernel.qemu').strip()==b'1'
if args.action in ('inspect','tap'):
    run('shell','uiautomator','dump','/sdcard/linesight-release-ui.xml')
    raw=run('exec-out','cat','/sdcard/linesight-release-ui.xml')
    Path('.artifact-work/release/current-window.xml').write_bytes(raw)
    nodes=list(ET.fromstring(raw).iter('node'))
    if args.action=='inspect':
        for node in nodes:
            label=node.get('text') or node.get('content-desc')
            if label: print(node.get('bounds'),label.replace('\n',' / '))
    else:
        matches=[node for node in nodes if args.value in [node.get('text'),node.get('content-desc')] or args.value in node.get('content-desc','').split('\n')]
        if not matches: raise RuntimeError('Visible action missing: '+str(args.value))
        clickable=[node for node in matches if node.get('clickable')=='true']
        candidates=clickable or matches
        if not 0 <= args.occurrence < len(candidates): parser.error('Visible action occurrence is out of range')
        node=candidates[args.occurrence]
        x1,y1,x2,y2=map(int,re.findall(r'\d+',node.get('bounds')))
        run('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
elif args.action=='capture':
    name=args.value
    if not re.fullmatch(r'[a-zA-Z0-9-]+-emulator',name or ''): parser.error('Use a simple filename ending in -emulator')
    folder=Path('docs/product/linesight/acceptance')/args.batch/'png';folder.mkdir(parents=True,exist_ok=True)
    (folder/(name+'.png')).write_bytes(run('exec-out','screencap','-p'))
    run('shell','uiautomator','dump','/sdcard/linesight-release-ui.xml')
    xml_folder=folder.parent/'ui';xml_folder.mkdir(parents=True,exist_ok=True)
    (xml_folder/(name+'.xml')).write_bytes(run('exec-out','cat','/sdcard/linesight-release-ui.xml'))
elif args.action=='back': run('shell','input','keyevent','4')
elif args.action=='swipe':
    # Respect the device's current size, including any wm size override.
    sizes=re.findall(r'(\d+)x(\d+)',run('shell','wm','size').decode())
    width,height=map(int,sizes[-1])
    run('shell','input','swipe',str(width//2),str(int(height*.85)),str(width//2),str(int(height*.3)),'350')
elif args.action=='launch': run('shell','am','start','-n','com.example.linesight_flutter/.MainActivity')
