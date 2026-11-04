"""Test the actual moon package ZIP from a separate consumer workspace."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

archive=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='consumer-',dir=archive.parent) as tmp:
    root=Path(tmp); library=root/'library'; library.mkdir()
    with zipfile.ZipFile(archive) as z:
        for name in z.namelist():
            target=(library/name).resolve()
            if not target.is_relative_to(library): raise ValueError('archive traversal')
        z.extractall(library)
        assert 'scripts/codec.py' in z.namelist()
        assert 'scripts/host.py' in z.namelist()
    consumer=root/'consumer'; consumer.mkdir()
    (root/'moon.work').write_text('members = ["library", "consumer"]\n')
    (consumer/'moon.mod').write_text('name = "local/archive-consumer"\nimport { "local/moonsquash@0.2.0" }\n')
    (consumer/'moon.pkg').write_text('import { "local/moonsquash" @squash }\noptions("is-main": true)\n')
    (consumer/'main.mbt').write_text('''///|
fn main raise {
  let image = @squash.open_image(@squash.build_image([
    {path:"/a",mode:420,content:Regular(b"consumer")},
    {path:"/b",mode:420,content:Hardlink("/a")},
  ],attributes=Map([("/a",{uid:10U,gid:20U,mtime:30U,xattrs:[{name:b"user.check",value:b"yes"}]})])))
  let a = image.lookup("/a")
  let b = image.lookup("/b")
  assert_eq(a.reference,b.reference)
  assert_eq(image.read_range(b,0,8),b"consumer")
  assert_eq(image.xattrs(a)[0].value,b"yes")
  assert_eq(image.verify().files,1)
  assert_eq(@squash.diff_images(image,image).length(),0)
  println("archive consumer passed")
}
''')
    for target in ['js','wasm-gc']:
        p=subprocess.run(['moon','run','.', '--target',target],cwd=consumer,capture_output=True,text=True)
        if p.returncode or 'archive consumer passed' not in p.stdout:
            raise RuntimeError(p.stdout+p.stderr)
        print(json.dumps({'archive_consumer':target,'result':'passed'}))
