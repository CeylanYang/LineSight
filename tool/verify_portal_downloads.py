"""Read-only public HTTPS download and legacy upgrade acceptance."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import platform
from pathlib import Path
import urllib.request


BASE = 'https://99ai.pronhubcn.com'


def fetch(path):
    with urllib.request.urlopen(BASE + path, timeout=120) as response:
        sha = hashlib.sha256()
        size = 0
        for block in iter(lambda: response.read(1024 * 1024), b''):
            sha.update(block)
            size += len(block)
        return {'path': path, 'final_url': response.url, 'status': response.status,
                'bytes': size, 'sha256': sha.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deployment', required=True)
    parser.add_argument('--evidence', required=True)
    parser.add_argument('--proxy', help='Optional HTTP proxy for this machine')
    args = parser.parse_args()
    if args.proxy:
        urllib.request.install_opener(urllib.request.build_opener(
            urllib.request.ProxyHandler({'http': args.proxy, 'https': args.proxy})))
    deployed = json.loads(Path(args.deployment).read_text(encoding='utf-8'))
    checks = [('/' + name, sha) for name, sha in deployed['files'].items()]
    checks.extend([('/linesight/', deployed['files']['index.html']),
                   ('/', deployed['files']['index.html'])])
    preview_name = 'downloads/' + deployed['aliases']['downloads/LineSight-legacy-upgrade.apk']
    preview = deployed['files'][preview_name]
    # Validate real old bookmark redirects through their stable compatible alias.
    checks.extend((prefix + '/downloads/LineSight-1.1.20-arm64-v8a.apk', preview)
                  for prefix in ('', '/linesight'))
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(fetch, [path for path, _ in checks]))
    for result, (_, expected) in zip(results, checks):
        assert result['sha256'] == expected, result
        if '1.1.20' in result['path']:
            assert result['final_url'].endswith('/LineSight-legacy-upgrade.apk'), result
    evidence = {'public_https_hashes_passed': True, 'checks': results,
                'verification_host': platform.node(),
                'verification_vantage': 'requesting host, using public DNS and trusted HTTPS',
                'registration_or_identity_changes': False,
                'browser_layout_verified': False}
    Path(args.evidence).write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print(json.dumps(evidence, indent=2))


if __name__ == '__main__':
    main()
