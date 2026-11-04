///|
fn uint_field(item : Json, key : String, default : UInt) -> UInt raise {
  guard item is Object(fields) else { fail("expected object") }
  match fields.get(key) {
    None => default
    Some(Number(n, ..)) => {
      guard n >= 0.0 && n <= 4294967295.0 && n.to_uint().to_double() == n else {
        fail("invalid integer: \{key}")
      }
      n.to_uint()
    }
    _ => fail("expected integer: \{key}")
  }
}

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
  let attributes : Map[String, @squash.BuildMetadata] = Map([])
  let created = uint_field(json, "created", 0U)
  for item in items {
    guard item is { "path": String(path), .. } else {
      fail("build entry needs path")
    }
    let content = match item {
      { "source": String(source), .. } => {
        guard read_bytes(source) is Some(data) else {
          fail("cannot read source: \{source}")
        }
        @squash.Regular(data)
      }
      { "symlink": String(target), .. } =>
        @squash.Symbolic(@utf8.encode(target))
      { "hardlink": String(target), .. } => @squash.Hardlink(target)
      { "directory": True, .. } => @squash.Folder
      { "device": String(kind), .. } => {
        let number = uint_field(item, "number", 0U)
        match kind {
          "block" => @squash.BlockDevice(number)
          "char" => @squash.CharDevice(number)
          _ => fail("device must be block or char")
        }
      }
      { "fifo": True, .. } => @squash.Fifo
      { "socket": True, .. } => @squash.Socket
      _ => fail("entry needs source, link, directory, or special type")
    }
    let mode = uint_field(
      item,
      "mode",
      match content {
        Folder => 493U
        Symbolic(_) => 511U
        _ => 420U
      },
    )
    guard mode <= 4095U else { fail("invalid mode") }
    entries.push({ path, mode: mode.reinterpret_as_int(), content, })
    if !(content is Hardlink(_)) {
      let xattrs : Array[@squash.Xattr] = []
      if item is { "xattrs": Object(values), .. } {
        for name, value in values {
          let data = match value {
            String(s) => @utf8.encode(s)
            { "source": String(p), .. } => {
              guard read_bytes(p) is Some(b) else {
                fail("cannot read xattr source")
              }
              b
            }
            _ => fail("xattr value needs text or source file")
          }
          xattrs.push({ name: @utf8.encode(name), value: data, })
        }
      }
      attributes[path] = {
        uid: uint_field(item, "uid", 0U),
        gid: uint_field(item, "gid", 0U),
        mtime: uint_field(item, "mtime", created),
        xattrs,
      }
    }
  }
  let compression = match json {
    { "compression": String(s), .. } =>
      match s {
        "none" => 0
        "gzip" => 1
        "lzma" => 2
        "lzo" => 3
        "xz" => 4
        "lz4" => 5
        "zstd" => 6
        _ => fail("unknown compression")
      }
    _ => 1
  }
  let bs = uint_field(json, "block_size", 131072U)
  guard bs <= 1048576U else { fail("block size too large") }
  let result = @squash.build_image(
    entries,
    attributes~,
    created~,
    block_size=bs.reinterpret_as_int(),
    compression=if compression == 0 { 1 } else { compression },
    encode=if compression == 0 { None } else { Some(encode) },
    fragments=!(json is { "fragments": False, .. }),
    exportable=!(json is { "exportable": False, .. }),
  )
  guard write_new(output, result) else {
    fail("cannot create new output; existing paths are not overwritten")
  }
  println("built \{result.length()} bytes")
}
