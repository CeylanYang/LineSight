"""Small deterministic illustrated profile portraits; no external avatar service."""
import base64
from functools import lru_cache
import hashlib
import io
from PIL import Image, ImageDraw

@lru_cache(maxsize=256)
def portrait(seed):
    if not seed:
        return ''
    digest=hashlib.sha256(seed.encode()).digest()
    palette=['#4679c6','#2b8a82','#8366aa','#c17a4a','#566d91','#a15f82']
    color=palette[digest[0]%len(palette)]
    skins=['#f0c7a5','#dfb28f','#f4d7bc','#d4a585']
    skin=skins[digest[1]%len(skins)]
    image=Image.new('RGB',(192,192),'#eaf1fb');draw=ImageDraw.Draw(image)
    draw.ellipse((0,0,192,192),fill=color)
    draw.ellipse((31,124,161,246),fill='#f2f5fa')
    draw.rounded_rectangle((81,108,111,148),radius=12,fill=skin)
    draw.ellipse((53,31,139,139),fill='#313746')
    draw.ellipse((59,43,133,132),fill=skin)
    draw.pieslice((51,25,141,106),180,355,fill='#313746')
    if digest[2]%2:
        draw.polygon([(54,65),(61,32),(130,39),(141,80),(116,53),(91,59)],fill='#313746')
    for x in (80,112):
        draw.ellipse((x-3,82,x+3,88),fill='#373743')
    draw.arc((84,97,110,113),10,170,fill='#9f5c58',width=3)
    if digest[3]%3==0:
        for x in (65,101):draw.rounded_rectangle((x,76,x+30,96),radius=7,outline='#3f485a',width=3)
        draw.line((95,83,101,83),fill='#3f485a',width=3)
    draw.polygon([(75,144),(96,159),(117,144),(106,192),(85,192)],fill=color)
    image=image.resize((96,96),Image.Resampling.LANCZOS)
    output=io.BytesIO();image.save(output,format='PNG',optimize=True)
    return base64.b64encode(output.getvalue()).decode('ascii')
