"""Independent malformed-image regressions identified by the strict review."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

cli=str(Path(sys.argv[1]).resolve())
baseline='--baseline' in sys.argv
def run(*args):
    p=subprocess.run(args,capture_output=True,timeout=90)
    if p.returncode: raise RuntimeError(p.stderr.decode(errors='replace'))
    return p.stdout
def raw_locations(data,block,offset,count):
    locations=[]
    while len(locations)<count:
        word=struct.unpack_from('<H',data,block)[0]
        assert word & 32768
        size=word & 32767
        n=min(count-len(locations),size-offset)
        assert n>=0
        locations.extend(range(block+2+offset,block+2+offset+n))
        block+=size+2; offset=0
    return locations
def replace(data,locations,value):
    for index,b in zip(locations,value): data[index]=b

with tempfile.TemporaryDirectory(prefix='image-review-',dir=Path(cli).parent) as tmp:
    root=Path(tmp); source=root/'input'; source.mkdir()
    for i in range(1100): (source/(f'{i:04}-'+'long-name-'*9)).write_bytes(b'')
    official=root/'official.sqfs'
    run('mksquashfs',str(source),str(official),'-noappend','-no-progress','-processors','1','-noI')
    data=bytearray(official.read_bytes())
    ref=struct.unpack_from('<Q',data,32)[0]; table=struct.unpack_from('<Q',data,64)[0]
    positions=raw_locations(data,table+(ref>>16),ref&65535,52)
    header=bytes(data[i] for i in positions)
    assert struct.unpack_from('<H',header)[0]==8 and struct.unpack_from('<H',header,32)[0]>0
    replace(data,positions[40:44],struct.pack('<I',0x7fffffff))
    cases={'directory-index-offset':data}
    datafile=root/'data'; datafile.write_bytes(b'A'*64)
    spec=root/'spec.json'; spec.write_text(json.dumps({'compression':'none','fragments':False,'metadata_compression':False,
        'entries':[{'path':'/a','source':str(datafile)},{'path':'/b','source':str(datafile)}]}))
    built=root/'built.sqfs'; run('node',cli,'build',str(spec),str(built))
    data=bytearray(built.read_bytes()); table=struct.unpack_from('<Q',data,64)[0]
    first=40 if struct.unpack_from('<H',data,table+2)[0]==8 else 0
    locations=raw_locations(data,table,0,first+120)
    header=bytes(data[i] for i in locations)
    assert struct.unpack_from('<H',header,first)[0]==9 and struct.unpack_from('<H',header,first+60)[0]==9
    start=struct.unpack_from('<Q',header,first+16)[0]
    replace(data,locations[first+76:first+84],struct.pack('<Q',start+1))
    cases['overlapping-data']=data
    spec.write_text(json.dumps({'compression':'lz4','entries':[{'path':'/a','source':str(datafile)}]}))
    lz4=root/'lz4.sqfs'; run('node',cli,'build',str(spec),str(lz4))
    data=bytearray(lz4.read_bytes()); struct.pack_into('<I',data,98,2)
    cases['lz4-options-version']=data
    accepted=[]
    for name,data in cases.items():
        file=root/f'{name}.sqfs'; file.write_bytes(data)
        p=subprocess.run(['node',cli,'verify',str(file)],capture_output=True,timeout=90)
        if p.returncode==0: accepted.append(name)
    print(json.dumps({'invalid_images':len(cases),'unexpectedly_accepted':accepted}))
    if not baseline: assert not accepted
