from pathlib import Path
import json,re,statistics
root=Path('build')
logs={}
for label,file in [('baseline','startup-baseline.log'),('worker','startup-worker.log')]:
    logs[label]=[json.loads(v) for v in re.findall(r'STARTUP_PROFILE (\{[^\r\n]+\})',(root/file).read_text(encoding='utf-8-sig'))]
    assert len(logs[label])==9
summary=[]
for scenario in ['small','large','large-with-undo']:
    row={'scenario':scenario}
    for label in logs:
        entries=[e for e in logs[label] if e['scenario']==scenario]
        assert len(entries)==3
        row[label]={'medianMs':statistics.median(e['elapsedUs'] for e in entries)/1000,'medianMaxGapMs':statistics.median(e['maxHeartbeatGapUs'] for e in entries)/1000,'workspaceBytes':entries[0]['workspaceBytes']}
    assert row['baseline']['workspaceBytes']==row['worker']['workspaceBytes']
    row['elapsedReductionPercent']=100*(1-row['worker']['medianMs']/row['baseline']['medianMs'])
    row['gapReductionPercent']=100*(1-row['worker']['medianMaxGapMs']/row['baseline']['medianMaxGapMs'])
    summary.append(row)
(root/'startup-comparison.json').write_text(json.dumps({'observations':logs,'summary':summary},indent=2),encoding='utf-8')
print(json.dumps(summary,indent=2))
