"""Bounded mean-shift / Canny / Zhang-Suen image processing."""
import base64
import binascii
import time
import cv2
import numpy as np
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle

ALGORITHM = 'mean-shift-canny-zhang-suen-v1'

def skeletonize(binary):
    """Zhang-Suen topology-preserving thinning with simultaneous subiterations."""
    pixels = np.pad((binary > 0).astype(np.uint8), 1)
    while True:
        changed = False
        for phase in (0, 1):
            p = pixels[1:-1,1:-1]
            n = [pixels[:-2,1:-1],pixels[:-2,2:],pixels[1:-1,2:],pixels[2:,2:],
                 pixels[2:,1:-1],pixels[2:,:-2],pixels[1:-1,:-2],pixels[:-2,:-2]]
            count = sum(n)
            transitions = sum(((n[i] == 0) & (n[(i+1)%8] == 1)).astype(np.uint8) for i in range(8))
            a, b = ((n[0]*n[2]*n[4], n[2]*n[4]*n[6]) if phase == 0 else
                    (n[0]*n[2]*n[6], n[0]*n[4]*n[6]))
            remove = (p == 1) & (count >= 2) & (count <= 6) & (transitions == 1) & (a == 0) & (b == 0)
            if np.any(remove):
                p[remove] = 0
                changed = True
        if not changed:
            return pixels[1:-1,1:-1]*255

def edge_image(decoded, max_side=1280):
    if decoded is None or decoded.ndim != 3 or not decoded.size:
        raise ValueError('Invalid image')
    height,width = decoded.shape[:2]
    scale = min(1.0,max_side/max(width,height))
    if scale < 1:
        decoded = cv2.resize(decoded,(max(1,round(width*scale)),max(1,round(height*scale))),interpolation=cv2.INTER_AREA)
    smooth = cv2.pyrMeanShiftFiltering(decoded,sp=12,sr=24,maxLevel=1)
    edges = cv2.Canny(cv2.cvtColor(smooth,cv2.COLOR_BGR2GRAY),50,150,L2gradient=True)
    skeleton = skeletonize(edges)
    preview = np.full((*skeleton.shape,3),255,dtype=np.uint8)
    preview[skeleton > 0] = (246,120,52)  # BGR, matching the existing blue reference.
    ok,png = cv2.imencode('.png',preview)
    if not ok: raise ValueError('Encoding failed')
    return png.tobytes(),skeleton

def camera_image(data):
    width,height=data.get('width'),data.get('height')
    if type(width) is not int or type(height) is not int or not 16<=width<=640 or not 16<=height<=640 or width*height>307200:
        raise ValueError('Frame dimensions invalid')
    planes=data.get('planes',[])
    if not isinstance(planes,list) or len(planes) not in (1,3): raise ValueError('Frame planes invalid')
    def plane(index,w,h):
        item=planes[index]; stride=item.get('row_stride'); step=item.get('pixel_stride',1)
        if type(stride) is not int or type(step) is not int or not 1<=step<=4 or stride<(w-1)*step+1 or stride>8192:
            raise ValueError('Frame stride invalid')
        raw=base64.b64decode(item['bytes'],validate=True)
        if len(raw) < (h-1)*stride+(w-1)*step+1 or len(raw)>3_000_000:
            raise ValueError('Frame buffer invalid')
        return np.ndarray((h,w),dtype=np.uint8,buffer=raw,strides=(stride,step)).copy()
    kind=data.get('format')
    if kind=='yuv420' and len(planes)==3 and width%2==0 and height%2==0:
        y=plane(0,width,height); u=plane(1,width//2,height//2); v=plane(2,width//2,height//2)
        packed=np.concatenate([y.ravel(),u.ravel(),v.ravel()]).reshape(height*3//2,width)
        decoded=cv2.cvtColor(packed,cv2.COLOR_YUV2BGR_I420)
    elif kind=='bgra8888' and len(planes)==1:
        item=planes[0]; stride=item.get('row_stride')
        if type(stride) is not int or not width*4<=stride<=8192: raise ValueError('BGRA stride invalid')
        raw=base64.b64decode(item['bytes'],validate=True)
        if len(raw)<height*stride or len(raw)>3_000_000: raise ValueError('BGRA buffer invalid')
        decoded=cv2.cvtColor(np.ndarray((height,width,4),dtype=np.uint8,buffer=raw,strides=(stride,4,1)),cv2.COLOR_BGRA2BGR)
    else: raise ValueError('Frame format unsupported')
    rotation=data.get('rotation',0)
    if rotation not in (0,90,180,270): raise ValueError('Rotation invalid')
    if rotation: decoded=cv2.rotate(decoded,{90:cv2.ROTATE_90_CLOCKWISE,180:cv2.ROTATE_180,270:cv2.ROTATE_90_COUNTERCLOCKWISE}[rotation])
    if data.get('mirror') is True: decoded=cv2.flip(decoded,1)
    return decoded

class VisionThrottle(UserRateThrottle):
    rate='3/second'

@api_view(['POST'])
@permission_classes([IsAuthenticated])
@throttle_classes([VisionThrottle])
def frame(request,workspace_id):
    from .api import membership
    membership(request,workspace_id)
    start=time.perf_counter()
    try:
        if len(request.body)>1_500_000: raise ValueError('Frame too large')
        decoded=camera_image(request.data)
        png,edges=edge_image(decoded,max_side=640)
        ok,original=cv2.imencode('.png',decoded)
        if not ok: raise ValueError('Encoding failed')
    except (ValueError,TypeError,KeyError,IndexError,binascii.Error,cv2.error):
        return Response({'detail':'无法读取相机画面，请重新开启相机'},status=400)
    return Response({'algorithm':ALGORITHM,'width':edges.shape[1],'height':edges.shape[0],
        'processing_ms':round((time.perf_counter()-start)*1000),
        'edge_png':base64.b64encode(png).decode(),'original_png':base64.b64encode(original).decode()}, headers={'Cache-Control':'no-store'})

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def lookup(request,workspace_id):
    from .api import membership,job_json
    member=membership(request,workspace_id)
    code=str(request.query_params.get('code','')).strip()
    if not code or len(code)>160: return Response({'detail':'请输入有效的批次号或工件编号'},status=400)
    from django.db.models import Q
    from .models import PieceSerial
    ids=PieceSerial.objects.filter(workspace=member.workspace,serial=code).values('job_id')
    rows=member.workspace.jobs.filter(Q(batch_code=code)|Q(pk__in=ids)).order_by('-created_at')[:101]
    jobs=[]
    for row in rows[:100]:
        value=job_json(row)
        if code in row.serial_numbers:
            latest=row.quality_inspections.order_by('-round_no','-id').first()
            value['matched_serial']=code
            value['piece_verdict']=latest.serial_results.get(code) if latest else None
            value['piece_round']=latest.round_no if latest else None
        jobs.append(value)
    return Response({'code':code,'jobs':jobs,'truncated':len(rows)>100})
