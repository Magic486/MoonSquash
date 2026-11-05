///|
extern "js" fn args() -> FixedArray[String] =
  #| () => process.argv.slice(2)

///|
extern "js" fn read_bytes(path : String) -> Bytes? =
  #| (path) => { try { const fs = require('node:fs'); const stat = fs.statSync(path); if (!stat.isFile() || stat.size > 536870912) return undefined; return new Uint8Array(fs.readFileSync(path)); } catch { return undefined; } }

///|
extern "js" fn stdout_bytes(data : Bytes) -> Unit =
  #| (data) => { process.stdout.write(Buffer.from(data)); }

///|
extern "js" fn write_new(path : String, data : Bytes) -> Bool =
  #| (path,data) => { const fs=require('node:fs'),p=require('node:path'); let temp,fd;
  #| try {temp=p.join(p.dirname(path),'.moonsquash-write-'+require('node:crypto').randomBytes(12).toString('hex'));
  #| fd=fs.openSync(temp,'wx',0o644);fs.writeFileSync(fd,data);fs.fsyncSync(fd);fs.closeSync(fd);fd=undefined;
  #| fs.linkSync(temp,path);return true;
  #| } catch {return false;} finally {if(fd!==undefined)fs.closeSync(fd);if(temp){try{fs.unlinkSync(temp);}catch{}}} }

///|
extern "js" fn report_error(message : String) -> Unit =
  #| (message) => { process.stderr.write(message + '\n'); process.exitCode = 1; }

///|
fn decode(
  id : Int,
  data : Bytes,
  limit : Int,
) -> Bytes raise @squash.SquashError {
  guard codec_host("decode", id, data, limit) is Some(result) else {
    raise @squash.Invalid(
      0,
      "decompressor unavailable, invalid stream, or output limit (ID \{id})",
    )
  }
  result
}

///|
fn run() -> Unit raise {
  let argv = args()
  if (argv.length() == 3 || argv.length() == 4) && argv[0] == "pack" {
    pack_command(
      argv[1],
      argv[2],
      if argv.length() == 4 {
        argv[3]
      } else {
        "gzip"
      },
    )
    return
  }
  if argv.length() == 3 && argv[0] == "build" {
    build_command(argv[1], argv[2])
    return
  }
  guard argv.length() >= 2 else {
    fail(
      "usage: moonsquash <info|tree|cat|verify|xattrs|diff|extract> IMAGE [PATH]",
    )
  }
  let fd = open_fd(argv[1])
  guard fd >= 0 else { fail("cannot open regular image (limit below 2 GiB)") }
  defer close_fd(fd)
  let image = source(fd)
  match argv[0] {
    "info" => {
      let h = image.header()
      println(
        Json::object({
          "inodes": @json.to_json(h.inodes),
          "block_size": @json.to_json(h.block_size),
          "fragments": @json.to_json(h.fragments),
          "compression": @json.to_json(h.compression),
          "bytes_used": @json.to_json(h.bytes_used),
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
            "path": @json.to_json(e.path),
            "inode": @json.to_json(e.inode.number),
            "kind": @json.to_json(e.inode.kind),
            "mode": @json.to_json(e.inode.mode),
            "uid": @json.to_json(e.inode.uid),
            "gid": @json.to_json(e.inode.gid),
            "mtime": @json.to_json(e.inode.mtime),
            "links": @json.to_json(e.inode.links),
            "size": @json.to_json(size),
          })
        })
      println(Json::array(result).stringify())
    }
    "cat" => {
      guard argv.length() == 3 else { fail("cat needs an absolute image path") }
      let node = image.lookup(argv[2])
      match node.content {
        Symlink(target) => stdout_bytes(target)
        _ => {
          guard node.content is File(_, size, _, _, _) else {
            fail("not a regular file")
          }
          let mut at = 0
          while at < size {
            let n = Int::min(1048576, size - at)
            stdout_bytes(image.read_range(node, at, n))
            at += n
          }
        }
      }
    }
    "verify" => {
      let r = image.verify()
      println(
        Json::object({
          "entries": @json.to_json(r.entries),
          "inodes": @json.to_json(r.inodes),
          "files_read": @json.to_json(
            image
            .tree()
            .filter(e => e.inode.content is File(_, _, _, _, _))
            .length(),
          ),
          "unique_files": @json.to_json(r.files),
          "bytes_checked": @json.to_json(r.bytes_checked),
          "xattrs": @json.to_json(r.xattrs),
          "fragments": @json.to_json(r.fragments),
          "export_checked": @json.to_json(r.export_checked),
        }).stringify(),
      )
    }
    "diff" => {
      guard argv.length() == 3 else { fail("diff needs two images") }
      let other_fd = open_fd(argv[2])
      guard other_fd >= 0 else { fail("cannot open second image") }
      defer close_fd(other_fd)
      let changes = @squash.diff_images(image, source(other_fd))
      println(
        Json::array(
          changes.map(d => {
            Json::object({
              "path": @json.to_json(d.path),
              "changes": @json.to_json(d.changes),
            })
          }),
        ).stringify(),
      )
    }
    "xattrs" => {
      guard argv.length() == 3 else { fail("xattrs needs an image path") }
      println(attrs_json(image.xattrs(image.lookup(argv[2]))).stringify())
    }
    "extract" => {
      guard argv.length() == 3 else {
        fail("extract needs a new output directory")
      }
      extract_command(image, argv[2])
    }
    _ => fail("unknown command")
  }
}
