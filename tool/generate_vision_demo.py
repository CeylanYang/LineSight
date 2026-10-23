"""Rebuild reference contours with the production algorithm and printable trace codes."""
import hashlib
import io
import json
import sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image
import qrcode
from barcode import Code128
from barcode.writer import ImageWriter

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'backend'))
from collaboration.vision import edge_image, ALGORITHM

folder=root/'docs/product/linesight/acceptance/vision-batch'
folder.mkdir(parents=True,exist_ok=True)
assets=[]
for source in sorted((root/'assets/parts').glob('part-*.webp')):
    if '-edge' in source.stem or '-wide' in source.stem: continue
    decoded=cv2.imdecode(np.frombuffer(source.read_bytes(),dtype=np.uint8),cv2.IMREAD_COLOR)
    png,_=edge_image(decoded)
    target=source.with_name(source.stem+'-edge.webp')
    Image.open(io.BytesIO(png)).save(target,format='WEBP',lossless=True)
    assets.append({'source':source.relative_to(root).as_posix(),'output':target.relative_to(root).as_posix(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    if source.stem=='part-mount':
        Image.open(source).save(folder/'reference-original-source.png')
        (folder/'reference-contour-processed.png').write_bytes(png)

fixture=json.loads((root/'docs/product/linesight/acceptance/history-batch/live-history.json').read_text(encoding='utf-8'))
batch=fixture['serial_numbers'][0].rsplit('-',1)[0]
codes={'task':f"linesight://task/{fixture['workspace_id']}/{fixture['job_id']}",
       'batch':batch,'piece':fixture['serial_numbers'][0]}
for name,value in codes.items():
    qrcode.make(value).save(folder/f'{name}-qr-generated.png')
    if name!='task':
        Code128(value,writer=ImageWriter()).save(str(folder/f'{name}-barcode-generated'),options={'module_width':0.4,'module_height':24,'quiet_zone':8,'font_size':13,'dpi':200})
(folder/'generated-assets.json').write_text(json.dumps({'algorithm':ALGORITHM,'reference_assets':assets,'codes':codes,'demo_only':True},indent=2)+'\n',encoding='utf-8')
print(f'{len(assets)} reference contours and 5 printable trace codes generated')
