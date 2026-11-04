"""Regression cases for lossy/ambiguous build specifications found in review."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

cli=str(Path(sys.argv[1]).resolve())
baseline='--baseline' in sys.argv
with tempfile.TemporaryDirectory(prefix='spec-review-',dir=Path(cli).parent) as tmp:
    root=Path(tmp); data=root/'input'; data.write_bytes(b'value')
    entry={'path':'/f','source':str(data)}
    cases=[
        {'entries':[dict(entry,directory=True)]},
        {'entries':[dict(entry,xattrs=[])]},
        {'entries':[entry],'compression':42},
        {'entries':[entry],'fragments':'false'},
        {'entries':[entry],'exportable':None},
        {'entries':[dict(entry,uidd=123)]},
        {'entries':[entry,{'path':'/a','hardlink':'/f','uid':123}]},
        {'entries':[entry,{'path':'/a','hardlink':'/f','xattrs':{'user.lost':'value'}}]},
    ]
    accepted=[]
    for i,spec in enumerate(cases):
        path=root/f'spec-{i}.json'; path.write_text(json.dumps(spec))
        out=root/f'{i}.sqfs'
        p=subprocess.run(['node',cli,'build',str(path),str(out)],capture_output=True)
        if p.returncode==0: accepted.append(i)
        elif not baseline: assert not out.exists()
    print(json.dumps({'invalid_specifications':len(cases),'unexpectedly_accepted':accepted}))
    if not baseline: assert not accepted
