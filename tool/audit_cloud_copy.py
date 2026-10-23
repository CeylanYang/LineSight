"""Check literal application translations on the three primary cloud UI modules.

This does not translate user-entered data or prove coverage of dynamic messages.
"""
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
known = set(json.loads((root / 'tool/l10n_source.json').read_text(encoding='utf-8')).values())
pattern = re.compile(r"(?:\btr\(\s*context,\s*|\b(?:group|field)\(\s*)'((?:\\.|[^'\\])*)'")
checked, missing, interpolated = set(), [], []
for name in ['cloud_shell', 'cloud_business', 'cloud_tasks']:
    path = root / 'lib/screens' / (name + '.dart')
    for match in pattern.finditer(path.read_text(encoding='utf-8')):
        text = re.sub(r'\\(.)', lambda m: {'n':'\n','r':'\r','t':'\t'}.get(m[1],m[1]), match[1])
        checked.add(text)
        if '${' in text:
            interpolated.append({'module':name,'text':text})
        elif text not in known:
            missing.append({'module':name,'text':text})
report = {'scope':'Literal tr(context, text), group(text) and field(text) calls in cloud_shell/cloud_business/cloud_tasks',
          'unique_literals_checked':len(checked), 'missing':missing, 'runtime_interpolation':interpolated,
          'dynamic_messages_and_user_content_audited':False}
print(json.dumps(report,ensure_ascii=False,indent=2))
assert not missing and not interpolated, 'Cloud copy needs translation or numbered placeholders'
