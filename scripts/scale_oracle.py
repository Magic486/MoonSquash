"""Measured synthetic root-tree workload; no claims of real firmware provenance."""
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile

cli=str(Path(sys.argv[1]).resolve())
host=str(Path(sys.argv[2]).resolve())
results={}
def run(*args):
    p=subprocess.run(args,capture_output=True,timeout=240)
    if p.returncode: raise RuntimeError(f'{args[0]}: {p.stderr.decode(errors="replace")}')
    return p.stdout
def measured(label,*args):
    metrics=root/f'{label}.metrics'
    result=run('/usr/bin/time','-f','{"seconds":%e,"max_rss_kib":%M}','-o',str(metrics),*args)
    results[label]=json.loads(metrics.read_text())
    return result
def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        while chunk:=stream.read(1048576): h.update(chunk)
    return h.hexdigest()

with tempfile.TemporaryDirectory(prefix='scale-review-',dir=Path(cli).parent) as tmp:
    root=Path(tmp); src=root/'input'; src.mkdir()
    files=[]
    for i in range(2400):
        folder=src/f'service-{i%24:02d}'; folder.mkdir(exist_ok=True)
        file=folder/f'config-{i:04d}.txt'
        file.write_bytes((f'service={i}\nport={10000+i}\n'.encode()*20))
        files.append(file.relative_to(src))
    large=src/'large-log'; block=(b'2026-11-05 service healthy request completed\n'*25000)[:1048576]
    # Default 88 MiB of compressible data plus 8 MiB of deterministic random bytes.
    assert len(block)==1048576
    with large.open('wb') as stream:
        log_mib=int(os.environ.get('MOONSQUASH_SCALE_MIB','88'))
        assert 1 <= log_mib <= 1024
        for _ in range(log_mib): stream.write(block)
    randomfile=src/'random.bin'; rng=random.Random(735)
    with randomfile.open('wb') as stream:
        for _ in range(8): stream.write(rng.randbytes(1048576))
    files += [Path('large-log'),Path('random.bin')]
    os.link(large,src/'large-alias'); files.append(Path('large-alias'))
    os.symlink('../large-log',src/'service-00/log')
    os.setxattr(src/'service-00','user.profile',b'scale-review')
    for path in [src,*src.rglob('*')]: os.utime(path,(1000000000,1000000000),follow_symlinks=False)
    image=root/'compressed.sqfs'
    measured('build_compressed','node',cli,'pack',str(src),str(image),'gzip')
    report=json.loads(measured('verify','node',cli,'verify',str(image)))
    assert report['unique_files']==2402
    # Capture a specification through the same host adapter, varying only
    # metadata encoding. The MoonBit builder still supplies both disk layouts.
    stage=root/'stage'; stage.mkdir()
    spec=json.loads(run('python3',host,'scan',str(src),str(stage),'gzip'))
    spec['metadata_compression']=False
    specfile=root/'spec.json'; specfile.write_text(json.dumps(spec))
    rawmeta=root/'raw-metadata.sqfs'
    measured('build_raw_metadata','node',cli,'build',str(specfile),str(rawmeta))
    assert json.loads(measured('semantic_diff','node',cli,'diff',str(rawmeta),str(image)))==[]
    again=root/'again.sqfs'; run('node',cli,'pack',str(src),str(again),'gzip')
    assert image.read_bytes()==again.read_bytes(), 'non-deterministic construction'
    official=root/'official.sqfs'
    measured('official_build','mksquashfs',str(src),str(official),'-comp','gzip','-noappend','-no-progress','-processors','1')
    json.loads(measured('official_image_verify','node',cli,'verify',str(official)))
    assert json.loads(run('node',cli,'diff',str(official),str(image)))==[]
    out=root/'official-extract'
    measured('official_extract','unsquashfs','-no-progress','-d',str(out),str(image))
    for path in files: assert digest(src/path)==digest(out/path),path
    assert (out/'large-log').stat().st_ino==(out/'large-alias').stat().st_ino
    assert os.getxattr(out/'service-00','user.profile')==b'scale-review'
    results.update({'unique_payload_bytes':int(report['bytes_checked']),'paths':report['entries'],
        'unique_inodes':report['inodes'],'unique_files':report['unique_files'],'file_paths_compared':len(files),
        'compressed_image_bytes':image.stat().st_size,'raw_metadata_image_bytes':rawmeta.stat().st_size,
        'deterministic':True,'semantic_diff_empty':True,'fixture':'synthetic, not real firmware'})
    print(json.dumps(results,indent=2))
