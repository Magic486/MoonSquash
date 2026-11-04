///|
extern "js" fn args() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn read_bytes(path : String) -> Bytes? =
  #| (path) => { try { const fs = require('node:fs'); const stat = fs.statSync(path); if (!stat.isFile() || stat.size > 536870912) return undefined; return new Uint8Array(fs.readFileSync(path)); } catch { return undefined; } }

///|
extern "js" fn inflate(data : Bytes, limit : Int) -> Bytes? =
  #| (data, limit) => { try { return new Uint8Array(require('node:zlib').inflateSync(data, {maxOutputLength:limit})); } catch { return undefined; } }

///|
extern "js" fn stdout_bytes(data : Bytes) -> Unit =
  #| (data) => { process.stdout.write(Buffer.from(data)); }

///|
extern "js" fn write_new(path : String, data : Bytes) -> Bool =
  #| (path, data) => { try { require('node:fs').writeFileSync(path, data, {flag:'wx'}); return true; } catch { return false; } }

///|
fn build_command(spec : String, output : String) -> Unit raise {
  guard read_bytes(spec) is Some(bytes) else {
    fail("cannot read build specification")
  }
  let json = @json.parse(@utf8.decode(bytes))
  guard json is { "entries": Array(items), .. } else {
    fail("build specification needs entries array")
  }
  let entries : Array[@squash.BuildEntry] = []
  for item in items {
    guard item is { "path": String(path), .. } else {
      fail("build entry needs path")
    }
    let content = match item {
      { "source": String(source), .. } => {
        guard read_bytes(source) is Some(data) else {
          fail("cannot read build source")
        }
        @squash.Regular(data)
      }
      { "symlink": String(target), .. } =>
        @squash.Symbolic(@utf8.encode(target))
      { "directory": True, .. } => @squash.Folder
      _ => fail("entry needs source, symlink or directory")
    }
    let mode = match content {
      Folder => 493
      Symbolic(_) => 511
      _ => 420
    }
    entries.push({ path, mode, content, })
  }
  let result = @squash.build_image(entries)
  guard write_new(output, result) else {
    fail("cannot create new output (existing paths are not overwritten)")
  }
  println("built \{result.length()} bytes")
}

///|
extern "js" fn report_error(message : String) -> Unit =
  #| (message) => { process.stderr.write(message + '\n'); process.exitCode = 1; }

///|
fn decode(
  id : Int,
  data : Bytes,
  limit : Int,
) -> Bytes raise @squash.SquashError {
  guard id == 1 else {
    raise @squash.Unsupported("CLI currently decodes gzip only (ID \{id})")
  }
  guard inflate(data, limit) is Some(result) else {
    raise @squash.Invalid(0, "gzip decompression failed or exceeded limit")
  }
  result
}

///|
fn run() -> Unit raise {
  let argv = args()
  if argv.length() == 3 && argv[0] == "build" {
    build_command(argv[1], argv[2])
    return
  }
  guard argv.length() >= 2 else {
    fail("usage: moonsquash <info|tree|cat|verify> IMAGE [PATH]")
  }
  guard read_bytes(argv[1]) is Some(bytes) else {
    fail("cannot read image (regular file, maximum 512 MiB)")
  }
  let image = @squash.open_image(bytes, decode~)
  match argv[0] {
    "info" => {
      let h = image.header()
      println(
        Json::object({
          "inodes": h.inodes.to_json(),
          "block_size": h.block_size.to_json(),
          "fragments": h.fragments.to_json(),
          "compression": h.compression.to_json(),
          "bytes_used": h.bytes_used.to_json(),
        }).stringify(),
      )
    }
    "tree" => {
      let result = image
        .tree()
        .map(e => {
          let size = match e.inode.content {
            File(_, size, _, _, _) => size
            Symlink(b) => b.length()
            _ => 0
          }
          Json::object({
            "path": e.path.to_json(),
            "inode": e.inode.number.to_json(),
            "kind": e.inode.kind.to_json(),
            "mode": e.inode.mode.to_json(),
            "uid": e.inode.uid.to_json(),
            "gid": e.inode.gid.to_json(),
            "size": size.to_json(),
          })
        })
      println(Json::array(result).stringify())
    }
    "cat" => {
      guard argv.length() == 3 else { fail("cat needs an absolute image path") }
      let node = image.lookup(argv[2])
      match node.content {
        Symlink(target) => stdout_bytes(target)
        _ => stdout_bytes(image.read_file(node))
      }
    }
    "verify" => {
      let entries = image.tree()
      let mut files = 0
      for e in entries {
        if e.inode.content is File(_, _, _, _, _) {
          ignore(image.read_file(e.inode))
          files += 1
        }
      }
      println(
        Json::object({
          "entries": entries.length().to_json(),
          "files_read": files.to_json(),
          "scope": "reachable tree and file data; xattrs and export index not yet verified".to_json(),
        }).stringify(),
      )
    }
    _ => fail("unknown command")
  }
}
