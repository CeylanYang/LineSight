"""Create a contact sheet from the captured Android screens."""
from pathlib import Path
import argparse
from PIL import Image, ImageDraw, ImageFont, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument('--version', choices=['v1.1', 'v1.1.2', 'v1.1.4', 'v1.1.5', 'v1.1.6', 'v1.1.7'], default='v1.1')
options = parser.parse_args()
root = Path(__file__).resolve().parents[1] / 'screenshots' / options.version
pages = [
    ('dashboard', '01 / WORKSPACE'), ('station', '02 / STATION'),
    ('record', '03 / EVIDENCE'), ('recipes', '04 / RECIPES'),
    ('statistics', '05 / INSIGHTS'), ('data-dark', '06 / LOCAL DATA'),
]
if options.version == 'v1.1.2':
    pages = [
        ('data-management', '01 / DATA MANAGEMENT'),
        ('restore-preview', '02 / RESTORE PREVIEW'),
        ('restore-record-detail', '03 / BEFORE & AFTER'),
        ('restore-point', '04 / RESTORE POINT'),
        ('record-audit', '05 / RECORD HISTORY'),
        ('audit-detail-dark', '06 / AUDIT DETAIL'),
    ]
elif options.version == 'v1.1.4':
    pages = [
        ('backup-formats', '01 / COMPLETE BACKUP'),
        ('backup-formats-dark', '02 / DARK APPEARANCE'),
        ('complete-backup', '03 / LARGE WORKSPACE'),
        ('verified-import', '04 / VERIFIED PREVIEW'),
        ('rejected-import', '05 / CORRUPT FILE REJECTED'),
        ('release-onboarding', '06 / RELEASE FIRST LAUNCH'),
    ]
elif options.version == 'v1.1.5':
    pages = [
        ('storage-failure', '01 / STARTUP RECOVERY'),
        ('recovery-select-backup', '02 / VERIFIED ADMIN'),
        ('recovery-preview', '03 / RECOVERY PREVIEW'),
        ('recovery-history', '04 / RECOVERY HISTORY'),
        ('recovery-original-dark', '05 / PRESERVED ORIGINALS'),
        ('release-onboarding', '06 / RELEASE FIRST LAUNCH'),
    ]
elif options.version == 'v1.1.6':
    pages = [
        ('csv-all', '01 / ALL RECORDS'),
        ('csv-filtered', '02 / FILTERED SELECTION'),
        ('csv-preview-dark', '03 / DARK PREVIEW'),
        ('csv-fields', '04 / FIELDS & SAVE'),
        ('csv-audit', '05 / VERIFIED FILE'),
        ('release-onboarding', '06 / RELEASE FIRST LAUNCH'),
    ]
elif options.version == 'v1.1.7':
    pages = [
        ('startup-light', '01 / STARTUP STATUS'),
        ('startup-dark', '02 / REDUCED MOTION'),
        ('release-onboarding', '03 / RELEASE SETUP'),
    ]
width, height, gap = 280, 622, 24
rows = (len(pages) + 2) // 3
sheet = Image.new('RGB', (3*width+4*gap, rows*(height+48)+(rows+1)*gap), '#eaf0f8')
draw = ImageDraw.Draw(sheet)
font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 15)
for i, (name, label) in enumerate(pages):
    x = gap+(i % 3)*(width+gap)
    y = gap+(i // 3)*(height+48+gap)
    draw.text((x, y+4), label, font=font, fill='#3478f6')
    screenshot = Image.open(root / f'{name}.png').convert('RGB')
    screenshot = ImageOps.contain(screenshot, (width, height), Image.Resampling.LANCZOS)
    sheet.paste(screenshot, (x+(width-screenshot.width)//2, y+34))
sheet.save(root / 'overview.jpg', quality=92)
print(root / 'overview.jpg')
