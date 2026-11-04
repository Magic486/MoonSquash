"""Focused host safety/permission regressions on synthetic owned directories."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cli=str(Path(sys.argv[1]).resolve())
def moon(*args, fail=False):
    p=subprocess.run(['node',cli,*map(str,args)],capture_output=True,timeout=60)
    if fail:
        assert p.returncode != 0
    elif p.returncode:
        raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout

with tempfile.TemporaryDirectory(prefix='host-regressions-',dir=Path(cli).parent) as temp:
    root=Path(temp)
    payload=root/'payload'; payload.write_bytes(b'never overwrite')
    spec=root/'spec.json'; spec.write_text(json.dumps({'entries':[
        {'path':'/','directory':True,'mode':0},
        {'path':'/dir','directory':True,'mode':0},
        {'path':'/dir/file','source':str(payload),'mode':0},
        {'path':'/alias','hardlink':'/dir/file'}
    ]}))
    image=root/'image'; moon('build',spec,image)
    previous=image.read_bytes(); moon('build',spec,image,fail=True); assert image.read_bytes()==previous
    symlink=root/'symlink'; symlink.symlink_to(payload)
    moon('build',spec,symlink,fail=True); assert payload.read_bytes()==b'never overwrite'
    output=root/'out'; moon('extract',image,output)
    assert output.stat().st_mode & 0o777 == 0
    os.chmod(output,0o700)
    assert (output/'dir').stat().st_mode & 0o777 == 0
    os.chmod(output/'dir',0o700)
    assert (output/'alias').stat().st_mode & 0o777 == 0
    os.chmod(output/'alias',0o600)
    assert (output/'alias').stat().st_ino==(output/'dir/file').stat().st_ino
    assert (output/'dir/file').read_bytes()==b'never overwrite'
    moon('extract',image,output,fail=True)
    source=root/'input'; source.mkdir(); (source/'file').write_bytes(b'stable')
    moon('pack',source,source/'bad.sqfs',fail=True)
    assert sorted(p.name for p in source.iterdir())==['file']
    assert (source/'file').read_bytes()==b'stable'
    print(json.dumps({'exclusive_build':True,'symlink_output_refused':True,'mode_zero_and_hardlinks':True,
                      'existing_extract_refused':True,'recursive_pack_refused':True}))
