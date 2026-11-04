"""Generate public synthetic fixtures; compare MoonBit with official SquashFS tools."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

cli = str(Path(sys.argv[1]).resolve())
def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f'{args[0]} exited {result.returncode}: {result.stderr.decode(errors="replace")}')
    return result.stdout

with tempfile.TemporaryDirectory(prefix='moonsquash-', dir=Path(cli).parent) as tmp:
    root = Path(tmp)
    source = root / 'input'
    source.mkdir()
    (source / 'nested').mkdir()
    files = {
        'hello.txt': b'MoonSquash interoperability\n',
        'empty': b'',
        'nested/big.bin': bytes(range(256)) * 1100,
        'nested/sparse': b'\0' * 200000 + b'END',
        'nested/unicode-月.txt': '月亮\n'.encode(),
    }
    for name, data in files.items():
        (source / name).write_bytes(data)
    os.link(source / 'hello.txt', source / 'hardlink')
    files['hardlink'] = files['hello.txt']
    os.symlink('../hello.txt', source / 'nested/link')
    # Force inode and directory metadata to cross the 8 KiB boundary.
    for i in range(350):
        name = f'nested/item-{i:04d}'
        files[name] = f'item {i}\n'.encode()
        (source / name).write_bytes(files[name])
    for mode, options in [('raw', ['-noI', '-noD', '-noF', '-noX']), ('gzip', [])]:
        image = root / (mode + '.sqfs')
        run('mksquashfs', str(source), str(image), '-noappend', '-comp', 'gzip', '-b', '4096', '-no-progress', '-processors', '1', *options)
        official = root / ('official-' + mode)
        run('unsquashfs', '-no-progress', '-d', str(official), str(image))
        entries = json.loads(run('node', cli, 'tree', str(image)))
        paths = {e['path'] for e in entries}
        assert paths == {'/', '/nested', '/nested/link'} | {'/' + n for n in files}, paths
        by_path = {e['path']: e for e in entries}
        assert by_path['/hardlink']['inode'] == by_path['/hello.txt']['inode']
        for name in ['hello.txt', 'empty', 'nested/big.bin', 'nested/sparse', 'nested/unicode-月.txt', 'hardlink', 'nested/item-0349']:
            result = run('node', cli, 'cat', str(image), '/' + name)
            assert result == files[name] == (official / name).read_bytes(), name
        assert run('node', cli, 'cat', str(image), '/nested/link') == b'../hello.txt'
        verification = json.loads(run('node', cli, 'verify', str(image)))
        assert verification['files_read'] == len(files)
        print(json.dumps({'mode': mode, 'entries': len(entries), 'files_read': verification['files_read'], 'byte_comparisons': 8, 'official': 'mksquashfs/unsquashfs'}, ensure_ascii=False))
    specification = root / 'build.json'
    specification.write_text(json.dumps({'compression':'none', 'entries': [
        *[{'path': '/' + name, 'source': str(source / name)} for name in files],
        {'path': '/nested/link', 'symlink': '../hello.txt'},
        {'path': '/emptydir', 'directory': True},
    ]}), encoding='utf-8')
    built = root / 'moon-built.sqfs'
    run('node', cli, 'build', str(specification), str(built))
    official = root / 'moon-official'
    run('unsquashfs', '-no-progress', '-d', str(official), str(built))
    for name, expected in files.items():
        assert (official / name).read_bytes() == expected, name
    assert os.readlink(official / 'nested/link') == '../hello.txt'
    assert (official / 'emptydir').is_dir()
    assert (official / 'hello.txt').stat().st_mode & 0o777 == 0o644
    run('node', cli, 'verify', str(built))
    print(json.dumps({'direction': 'MoonBit builder -> official unsquashfs', 'files_compared': len(files), 'symlink': True, 'empty_directory': True}))
