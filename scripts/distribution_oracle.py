"""Read/extract a pinned public OpenWrt root filesystem against official tools.

Download separately from the URL below. The fixture is not redistributed in the
package, mounted, installed or executed. Only the image tools process its data.
"""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

URL = ('https://downloads.openwrt.org/releases/24.10.0/targets/x86/64/'
       'openwrt-24.10.0-x86-64-generic-squashfs-rootfs.img.gz')
EXPECTED = '363a441352bc69540bf34e862d291bda3d574214621c440ba0fb9a478ab3459e'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


cli = str(Path(sys.argv[1]).resolve())
download = Path(sys.argv[2]).resolve()
assert digest(download) == EXPECTED, 'fixture differs from published checksum'
with tempfile.TemporaryDirectory(prefix='moonsquash-openwrt-') as tmp:
    root = Path(tmp)
    image = root / 'rootfs.sqfs'
    with gzip.open(download, 'rb') as source, image.open('wb') as target:
        shutil.copyfileobj(source, target)
    report = json.loads(run('node', cli, 'verify', str(image)))
    official, moon = root / 'official', root / 'moon'
    # This pinned image has one device inode. Compare its listing without
    # attempting privileged creation; extract all ordinary objects as a user.
    listing = run('unsquashfs', '-lln', str(image))
    console = [line for line in listing.splitlines() if line.endswith('/dev/console')]
    assert len(console) == 1 and console[0].startswith('c'), console
    run('unsquashfs', '-no-progress', '-no-xattrs', '-excludes',
        '-d', str(official), str(image), 'dev/console')
    extracted = json.loads(run('node', cli, 'extract', str(image), str(moon)))
    assert any(e['path'] == '/dev/console' and e.get('kind') == 5
               for e in extracted['not_restored'])
    assert not (moon / 'dev/console').exists()
    files = links = directories = specials = 0
    groups = {}
    for path in official.rglob('*'):
        relative = path.relative_to(official)
        other = moon / relative
        mode = path.lstat().st_mode
        if stat.S_ISREG(mode):
            assert other.is_file() and not other.is_symlink(), relative
            assert digest(path) == digest(other), relative
            key = path.stat().st_ino
            groups.setdefault(key, set()).add(other.stat().st_ino)
            assert len(groups[key]) == 1, relative
            files += 1
        elif stat.S_ISLNK(mode):
            assert other.is_symlink() and path.readlink() == other.readlink(), relative
            links += 1
        elif stat.S_ISDIR(mode):
            assert other.is_dir() and not other.is_symlink(), relative
            directories += 1
        else:
            specials += 1
    assert files == report['files_read']
    assert specials == 0
    specials = 1  # /dev/console was checked as a record, not created.
    assert files + links + directories + specials + 1 == report['entries']
    omissions = {}
    for entry in extracted.pop('not_restored'):
        reason = entry['reason']
        omissions[reason] = omissions.get(reason, 0) + 1
    extracted['omission_counts'] = omissions
    print(json.dumps({'distribution': 'OpenWrt 24.10.0 x86-64', 'source': URL,
                      'download_sha256': EXPECTED, 'verify': report,
                      'regular_paths_compared': files, 'symlinks_compared': links,
                      'directories_compared': directories, 'special_records': specials,
                      'extract': extracted}, ensure_ascii=False))
