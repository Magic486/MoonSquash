"""Independent full-profile verification using system mksquashfs/unsquashfs."""
import json
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
algorithms = os.environ.get('MOONSQUASH_TEST_CODECS','gzip,xz,zstd,lz4,lzo,lzma').split(',')
assert algorithms[0] == 'gzip' and set(algorithms) <= {'gzip','xz','zstd','lz4','lzo','lzma'}


def run(*args, ok=True):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180)
    if ok and p.returncode:
        raise RuntimeError(f"{args[0]} {args[1]}: exit {p.returncode}: {p.stderr.decode(errors='replace')}")
    if not ok:
        assert p.returncode != 0, args
    return p.stdout


def moon(*args, ok=True):
    return run('node', cli, *map(str,args), ok=ok)


with tempfile.TemporaryDirectory(prefix='moon-full-',dir=Path(cli).parent) as temp:
    root=Path(temp)
    src=root/'input'; src.mkdir(); (src/'dir').mkdir(); (src/'emptydir').mkdir()
    rng=random.Random(384)
    files={'large':b'abcd'*15000+rng.randbytes(11000),'sparse':b'\0'*16384+b'end','empty':b'','dir/utf8-月':b'binary\0\xff'}
    for i in range(160): files[f'dir/item-{i:04}']=(f'file {i}:'.encode()*180)[:1100]
    for name,data in files.items(): (src/name).write_bytes(data)
    os.link(src/'large',src/'alias')
    os.symlink('../large',src/'dir/link')
    os.mkfifo(src/'fifo',0o600)
    os.setxattr(src/'large','user.binary',b'\0\xffattribute')
    # Repeated large values cause official out-of-line xattr references.
    os.setxattr(src/'large','user.shared',b'z'*3000)
    os.setxattr(src/'dir/utf8-月','user.shared',b'z'*3000)
    os.setxattr(src/'dir','user.directory',b'dir')
    for p in [src,*src.rglob('*')]: os.utime(p,(123456789,123456789),follow_symlinks=False)
    official_images=[]
    for algorithm in algorithms:
        official=root/f'official-{algorithm}.sqfs'
        run('mksquashfs',str(src),str(official),'-comp',algorithm,'-b','4096','-noappend','-no-progress','-processors','1','-all-root')
        report=json.loads(moon('verify',official))
        assert report['unique_files']==len(files),report
        assert report['xattrs']==4,report  # hardlink attributes counted once
        for name in ['large','sparse','empty','dir/utf8-月']:
            assert moon('cat',official,'/'+name)==files[name]
        attrs=json.loads(moon('xattrs',official,'/large'))
        assert {bytes(a['name']):bytes(a['value']) for a in attrs}[b'user.binary']==b'\0\xffattribute'
        if official_images:
            assert json.loads(moon('diff',official_images[0],official))==[]
        official_images.append(official)
        print(json.dumps({'official_to_moon':algorithm,'report':report}),flush=True)
    # Build every compressor with ownership, hard links, xattrs and special inode models.
    data_xattr=root/'xattr.bin'; data_xattr.write_bytes(b'\0\xffattribute')
    entries=[{'path':'/'+name,'source':str(src/name),'uid':1234,'gid':5678,'mtime':123456789} for name in files]
    for e in entries:
        if e['path']=='/large': e['mode']=0o640; e['xattrs']={'user.binary':{'source':str(data_xattr)},'user.shared':'z'*3000}
    entries += [{'path':'/alias','hardlink':'/large'},{'path':'/dir/link','symlink':'../large'},
                {'path':'/emptydir','directory':True},{'path':'/fifo','fifo':True},
                {'path':'/char','device':'char','number':259},{'path':'/block','device':'block','number':2048},
                {'path':'/socket','socket':True}]
    images=[]
    for algorithm in ['none',*algorithms]:
        spec=root/f'{algorithm}.json'; spec.write_text(json.dumps({'entries':entries,'compression':algorithm,'block_size':4096,'created':0}))
        built=root/f'built-{algorithm}.sqfs'; moon('build',spec,built)
        report=json.loads(moon('verify',built))
        # List all special records, then extract only regular objects without privilege.
        listing=run('unsquashfs','-lln',str(built)).decode()
        assert '1234/5678' in listing and 'char' in listing and 'socket' in listing
        out=root/f'out-{algorithm}'
        run('unsquashfs','-no-progress','-d',str(out),str(built),*files,'alias','dir/link','emptydir')
        for name,data in files.items(): assert (out/name).read_bytes()==data,name
        assert (out/'alias').stat().st_ino==(out/'large').stat().st_ino
        assert os.readlink(out/'dir/link')=='../large'
        assert os.getxattr(out/'large','user.binary')==b'\0\xffattribute'
        assert (out/'large').stat().st_mode & 0o777 == 0o640
        assert int((out/'large').stat().st_mtime)==123456789
        if images: assert json.loads(moon('diff',images[0],built))==[]
        images.append(built)
        print(json.dumps({'moon_to_official':algorithm,'files':len(files),'bytes':built.stat().st_size,'report':report}),flush=True)
    extracted=root/'safe-extract'
    report=json.loads(moon('extract',images[1],extracted))
    for name,data in files.items(): assert (extracted/name).read_bytes()==data
    assert (extracted/'alias').stat().st_ino==(extracted/'large').stat().st_ino
    assert os.readlink(extracted/'dir/link')=='../large'
    assert os.getxattr(extracted/'large','user.binary')==b'\0\xffattribute'
    assert not (extracted/'char').exists()
    moon('extract',images[1],extracted,ok=False)
    assert (extracted/'large').read_bytes()==files['large']
    print(json.dumps({'safe_extract':True,'files':report['files'],'hardlinks':report['hardlinks']}),flush=True)
    packed=root/'packed.sqfs'; moon('pack',src,packed,'gzip')
    packed_report=json.loads(moon('verify',packed))
    assert packed_report['xattrs']==4
    # Official fixture is all-root; compare owner values separately for pack.
    packed_tree={e['path']:e for e in json.loads(moon('tree',packed))}
    assert packed_tree['/large']['uid']==os.getuid()
    assert packed_tree['/large']['inode']==packed_tree['/alias']['inode']
    assert packed_tree['/']['mtime']==123456789
    packed_out=root/'packed-out'
    run('unsquashfs','-no-progress','-d',str(packed_out),str(packed),*files,'alias','dir/link','emptydir')
    for name,data in files.items(): assert (packed_out/name).read_bytes()==data
    print(json.dumps({'directory_pack':True,'xattrs':packed_report['xattrs']}),flush=True)
    boundary=root/'indexed-directory'; boundary.mkdir()
    for i in range(1100):
        (boundary/(f'{i:04}-'+'long-name-'*9)).write_bytes(b'')
    boundary_image=root/'indexed-directory.sqfs'
    run('mksquashfs',str(boundary),str(boundary_image),'-comp','gzip','-noappend','-no-progress','-processors','1')
    boundary_report=json.loads(moon('verify',boundary_image))
    assert boundary_report['unique_files']==1100
    print(json.dumps({'official_large_directory':True,'inodes':boundary_report['inodes']}),flush=True)
    # A malicious link may be preserved, but cannot be traversed during writes.
    spec=root/'links.json'; spec.write_text(json.dumps({'entries':[
        {'path':'/escape','symlink':str(root)}, {'path':'/okay','source':str(src/'empty')}
    ]}))
    attack=root/'links.sqfs'; moon('build',spec,attack)
    attack_out=root/'links-out'; moon('extract',attack,attack_out)
    assert not (root/'okay').exists()
    # Header, reference, table and compressed payload mutations must fail cleanly.
    original=images[1].read_bytes()
    rejected=0
    for at in [0,4,12,22,28,32,40,48,56,64,72,80,88]:
        b=bytearray(original); b[at:at+4]=b'\xff'*4
        damaged=root/'bad.sqfs'; damaged.write_bytes(b)
        moon('verify',damaged,ok=False); rejected+=1
    for length in [0,95,len(original)-1]:
        damaged=root/'truncated.sqfs'; damaged.write_bytes(original[:length]); moon('verify',damaged,ok=False); rejected+=1
    b=bytearray(original); b[96]^=255
    damaged=root/'bad-data.sqfs'; damaged.write_bytes(b); moon('verify',damaged,ok=False); rejected+=1
    print(json.dumps({'malformed_images_rejected':rejected}),flush=True)
