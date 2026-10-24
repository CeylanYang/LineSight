"""Count actual DEX logging instructions without saving constants or raw disassembly."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('apk', type=Path)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--require-clean', action='store_true')
args = parser.parse_args()
dexdump = Path.home() / 'AppData/Local/Android/Sdk/build-tools/36.1.0/dexdump.exe'
calls = Counter()
with tempfile.TemporaryDirectory(prefix='linesight-log-audit-') as tmp:
    with zipfile.ZipFile(args.apk) as apk:
        dex_names = [n for n in apk.namelist() if re.fullmatch(r'classes\d*\.dex', n)]
        assert dex_names
        for name in dex_names:
            dex = Path(tmp) / name
            dex.write_bytes(apk.read(name))
            output = subprocess.check_output([str(dexdump), '-d', str(dex)]).decode(errors='replace')
            for line in output.splitlines():
                if 'invoke-' not in line:
                    continue
                log = re.search(r'Landroid/util/Log;\.(v|d|i|w|e|wtf|println):', line)
                if log:
                    calls['android.util.Log.' + log[1]] += 1
                if re.search(r'L[^;]+;\.printStackTrace:\(', line):
                    calls['printStackTrace'] += 1
report = {'apk_sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
          'dex_files': len(dex_names), 'direct_call_counts': dict(sorted(calls.items())),
          'direct_calls_absent': not calls,
          'scope': 'Direct DEX Log v/d/i/w/e/wtf/println and printStackTrace calls; excludes native libraries, reflection, other logging APIs and OS crash output',
          'raw_disassembly_saved': False}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
if args.require_clean and calls:
    raise SystemExit(1)
