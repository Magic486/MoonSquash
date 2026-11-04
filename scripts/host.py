#!/usr/bin/env python3
"""Filesystem adapter for verified MoonBit extraction plans. No image parsing.

The destination must not exist. A private mode-0700 root, no-follow parent
directory descriptors and exclusive file creation prevent image path traversal.
Ownership and privileged modes are reported, never silently applied.
"""
import json
import os
from pathlib import Path
import shutil
import stat
import sys


def extract(stage, destination, entries):
    if os.name != "posix":
        raise ValueError("safe extraction adapter requires Linux/POSIX")
    if not entries or entries[0]["path"] != "/":
        raise ValueError("missing root")
    seen = set()
    for e in entries:
        path = e["path"]
        parts = path.split("/")[1:]
        if path != "/" and (not path.startswith("/") or any(p in ("", ".", "..") or "\0" in p for p in parts)):
            raise ValueError("noncanonical extraction path")
        if path in seen:
            raise ValueError("duplicate extraction path")
        seen.add(path)
    os.mkdir(destination, 0o700)  # exclusive; refuses existing directories/symlinks
    root = os.open(destination, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    report = {"entries": len(entries), "files": 0, "hardlinks": 0,
              "symlinks": 0, "xattrs": 0, "not_restored": []}
    links = {}

    def parent(path):
        parts = path.split("/")[1:]
        fd = os.dup(root)
        try:
            for part in parts[:-1]:
                next_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
                os.close(fd)
                fd = next_fd
            return fd, parts[-1]
        except BaseException:
            os.close(fd)
            raise

    try:
        # Keep every directory private until all content and attributes are set.
        for e in sorted(entries[1:], key=lambda x: (x["path"].count("/"), x["path"])):
            fd, name = parent(e["path"])
            try:
                kind = e["kind"]
                if kind == 1:
                    os.mkdir(name, 0o700, dir_fd=fd)
                elif e["inode"] in links:
                    old = links[e["inode"]]
                    os.link(old, name, src_dir_fd=root, dst_dir_fd=fd, follow_symlinks=False)
                    report["hardlinks"] += 1
                elif kind == 2:
                    out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
                    with os.fdopen(out, "wb") as stream, open(Path(stage) / str(e["inode"]), "rb") as source:
                        shutil.copyfileobj(source, stream, 1048576)
                    report["files"] += 1
                    links[e["inode"]] = e["path"][1:]
                elif kind == 3:
                    os.symlink(bytes(e["target"]), os.fsencode(name), dir_fd=fd)
                    report["symlinks"] += 1
                    links[e["inode"]] = e["path"][1:]
                else:
                    report["not_restored"].append({"path": e["path"], "reason": "special inode; no device/FIFO/socket creation", "kind": kind})
            finally:
                os.close(fd)
        metadata_done = set()
        for e in sorted(entries, key=lambda x: 0 if x["path"] == "/" else x["path"].count("/"), reverse=True):
            if e["kind"] not in (1, 2, 3):
                continue
            if e["inode"] in metadata_done:
                continue
            metadata_done.add(e["inode"])
            fd, name = (os.dup(root), ".") if e["path"] == "/" else parent(e["path"])
            try:
                if e["uid"] != os.geteuid() or e["gid"] != os.getegid():
                    report["not_restored"].append({"path": e["path"], "reason": "ownership", "uid": e["uid"], "gid": e["gid"]})
                if e["mode"] & 0o7000:
                    report["not_restored"].append({"path": e["path"], "reason": "privileged mode bits", "mode": e["mode"]})
                if e["kind"] != 3:
                    node = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd)
                    try:
                        for a in e["xattrs"]:
                            key, value = bytes(a["name"]), bytes(a["value"])
                            if not key.startswith(b"user."):
                                report["not_restored"].append({"path":e["path"],"reason":"privileged xattr","name":list(key)})
                                continue
                            os.setxattr(node, key, value)
                            report["xattrs"] += 1
                        os.fchmod(node, e["mode"] & 0o777)
                        os.utime(node, (e["mtime"],e["mtime"]))
                    finally:
                        os.close(node)
                else:
                    os.utime(name,(e["mtime"],e["mtime"]),dir_fd=fd,follow_symlinks=False)
                    if e["xattrs"]:
                        report["not_restored"].append({"path":e["path"],"reason":"symlink xattrs"})
            finally:
                os.close(fd)
    finally:
        os.close(root)
    return report


def scan(source, stage, compression):
    source = Path(source).resolve(strict=True)
    if not source.is_dir():
        raise ValueError("pack source must be a directory")
    if Path(stage).resolve().is_relative_to(source):
        raise ValueError("pack output must be outside the source tree")
    entries, links = [], {}

    def walk(path, image_path, depth=0):
        if depth > 128 or len(entries) >= 10000:
            raise ValueError("pack tree limit")
        image_path.encode('utf-8')  # reject undecodable host names explicitly
        st = path.lstat()
        seconds=int(st.st_mtime)
        if st.st_mtime < 0 or not 0 <= seconds <= 4294967295:
            raise ValueError("mtime cannot be represented by SquashFS 4")
        e = {"path":image_path,"mode":stat.S_IMODE(st.st_mode),"uid":st.st_uid,"gid":st.st_gid,"mtime":seconds}
        identity = (st.st_dev,st.st_ino)
        if not stat.S_ISDIR(st.st_mode) and identity in links:
            entries.append({"path":image_path,"hardlink":links[identity]})
            return
        if stat.S_ISDIR(st.st_mode): e["directory"] = True
        elif stat.S_ISREG(st.st_mode): e["source"] = str(path)
        elif stat.S_ISLNK(st.st_mode):
            target = os.readlink(path); target.encode('utf-8'); e["symlink"] = target
        elif stat.S_ISFIFO(st.st_mode): e["fifo"] = True
        elif stat.S_ISSOCK(st.st_mode): e["socket"] = True
        elif stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode):
            e["device"] = 'char' if stat.S_ISCHR(st.st_mode) else 'block'
            major, minor = os.major(st.st_rdev), os.minor(st.st_rdev)
            if major > 4095 or minor > 1048575: raise ValueError("device number outside SquashFS encoding")
            e["number"] = (minor & 255) | (major << 8) | ((minor & ~255) << 12)
        else: raise ValueError("unknown host file type")
        if not stat.S_ISDIR(st.st_mode): links[identity] = image_path
        attrs = {}
        for name in sorted(os.listxattr(path,follow_symlinks=False)):
            name.encode('utf-8')
            value = os.getxattr(path,name,follow_symlinks=False)
            filename = Path(stage)/f'attr-{len(entries)}-{len(attrs)}'
            with filename.open('xb') as stream: stream.write(value)
            attrs[name] = {"source":str(filename)}
        e["xattrs"] = attrs
        entries.append(e)
        if stat.S_ISDIR(st.st_mode):
            for name in sorted(os.listdir(path), key=os.fsencode):
                walk(path/name,('/' if image_path=='/' else image_path+'/')+name,depth+1)
    walk(source,'/')
    return {"entries":entries,"compression":compression,"created":0}


if __name__ == "__main__":
    try:
        if sys.argv[1] == "extract":
            data = sys.stdin.buffer.read(16777217)
            if len(data) > 16777216:
                raise ValueError("extraction plan budget")
            result=extract(sys.argv[2],sys.argv[3],json.loads(data))
        elif sys.argv[1] == "scan":
            result=scan(sys.argv[2],sys.argv[3],sys.argv[4])
        else:
            raise ValueError("unknown host operation")
        print(json.dumps(result,ensure_ascii=False))
    except Exception as error:
        print(f"moonsquash host: {error}",file=sys.stderr)
        sys.exit(1)
