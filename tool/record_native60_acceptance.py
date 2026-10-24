"""Check captured native UI and exports; does not operate on user accounts."""
import csv
import hashlib
import io
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[1]
    folder = root / 'docs/product/linesight/acceptance/native60-batch'
    labels = {
        '333-native60-insights-emulator': ['55.6%', '96.8%', '63', '61'],
        '338-native60-diagnostics-emulator': ['连接正常', '本机草稿'],
        '339-native60-english-profile-emulator': ['Profile', 'Sync and drafts'],
        '340-native60-english-guide-emulator': ['Guide and app information', 'Sign-in and teams'],
        '341-native60-english-sync-emulator': ['All photos synced', 'No unsubmitted drafts'],
        '342-native60-english-notifications-emulator': ['14 pending notifications', '16 items'],
    }
    for name, expected in labels.items():
        tree = ET.parse(folder / 'ui' / (name + '.xml'))
        text = '\n'.join(n.get('text', '') + n.get('content-desc', '') for n in tree.iter('node'))
        assert all(label in text for label in expected), name
    metrics = {}
    for row in csv.reader(io.StringIO((folder / 'LineSight-quality.csv').read_text(encoding='utf-8-sig'))):
        if not row:
            break
        metrics[row[0]] = row[1]
    assert metrics['first_inspected_pieces'] == '63'
    assert metrics['final_released_pieces'] == '61'
    assert metrics['workspace'] == '演示团队'
    assert round(float(metrics['first_pass_rate']) * 100, 1) == 55.6
    assert round(float(metrics['final_release_rate']) * 100, 1) == 96.8
    poppler = Path.home() / 'AppData/Local/Programs/MiKTeX/miktex/bin/x64'
    pdf = folder / 'LineSight-quality.pdf'
    info = subprocess.check_output([str(poppler / 'pdfinfo.exe'), str(pdf)], text=True)
    assert 'Pages:           9' in info and '(A4)' in info
    text = subprocess.check_output([str(poppler / 'pdftotext.exe'), '-layout', str(pdf), '-']).decode('utf-8')
    assert all(value in text for value in ['55.6%', '96.8%', '最终放行工件', '演示团队'])
    captures = []
    for path in sorted((folder / 'png').glob('*.png')):
        with Image.open(path) as picture:
            assert picture.size == (412, 824)
        assert (folder / 'ui' / (path.stem + '.xml')).is_file()
        captures.append(path.name)
    assert len(captures) == 11
    exports = {p.name: {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
               for p in [pdf, folder / 'LineSight-quality.csv']}
    result = {
        'version': '1.1.54+8078', 'content_revision': 2,
        'device': 'Android API34 x86_64 emulator, 412x824', 'channel': 'preview',
        'workspace': 'independent demo team', 'captures': captures, 'exports': exports,
        'csv_pdf_ui_metrics_agree': True, 'pdf_pages': 9,
        'pdf_render_review': 'Nine rendered pages inspected; no unreadable glyphs or overlapping text. Task sections may continue across pages.',
        'report_return_after_export_observed': True, 'english_secondary_pages_observed': True,
        'language_restored_to_chinese': True, 'customer_business_data_modified': False,
        'app_reinstalled': False, 'app_data_cleared': False,
        'full_native_role_matrix_complete': False, 'physical_hardware_verified': False,
        'production_runtime_verified': False,
    }
    (folder / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Native60: 11 screenshot/XML pairs and CSV/PDF export checks passed.')


if __name__ == '__main__':
    main()
