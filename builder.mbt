///|
pub(all) enum BuildContent {
  Folder
  Regular(Bytes)
  Symbolic(Bytes)
  Hardlink(String)
  BlockDevice(UInt)
  CharDevice(UInt)
  Fifo
  Socket
} derive(Debug)

///|
pub(all) struct BuildEntry {
  path : String
  mode : Int
  content : BuildContent
} derive(Debug)

///|
priv struct BuildNode {
  path : String
  name : Bytes
  mode : Int
  content : BuildContent
  mut parent : Int
  children : Array[Int]
  mut raw_inode : Int
  mut raw_dir : Int
  mut dir_size : Int
  mut data_start : Int
  blocks : Array[UInt]
  mut sparse : Int
  mut target : Int
  mut number : Int
  mut links : Int
  mut fragment : UInt
  mut fragment_offset : Int
  mut xattr : UInt
}

///|
/// Per-path metadata. Hard links share the target inode's metadata.
pub(all) struct BuildMetadata {
  uid : UInt
  gid : UInt
  mtime : UInt
  xattrs : Array[Xattr]
} derive(Debug)

///|
fn build_kind(content : BuildContent) -> Int {
  match content {
    Folder => 1
    Regular(_) | Hardlink(_) => 2
    Symbolic(_) => 3
    BlockDevice(_) => 4
    CharDevice(_) => 5
    Fifo => 6
    Socket => 7
  }
}

///|
fn store_block(
  out : Array[Byte],
  data : Bytes,
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> UInt raise SquashError {
  if encode is Some(compress) {
    let packed = compress(compression, data)
    if packed.length() > 0 && packed.length() < data.length() {
      append_bytes(out, packed)
      return packed.length().reinterpret_as_uint()
    }
  }
  append_bytes(out, data)
  data.length().reinterpret_as_uint() | 0x1000000U
}

///|
/// Write a raw metadata table followed by its absolute block pointer index.
fn write_index(out : Array[Byte], raw : Array[Byte]) -> Int {
  let start = out.length()
  append_bytes(out, pack_metadata(raw))
  let table = out.length()
  for i in 0..<((raw.length() + 8191) / 8192) {
    put64(out, (start + i * 8194).to_uint64())
  }
  table
}

///|
fn put16(out : Array[Byte], n : Int) -> Unit {
  out.push((n & 255).to_byte())
  out.push(((n >> 8) & 255).to_byte())
}

///|
fn put32(out : Array[Byte], n : UInt) -> Unit {
  for i in 0..<4 {
    out.push(((n >> (i * 8)) & 255U).to_byte())
  }
}

///|
fn put64(out : Array[Byte], n : UInt64) -> Unit {
  put32(out, n.to_uint())
  put32(out, (n >> 32).to_uint())
}

///|
fn append_bytes(out : Array[Byte], bytes : Bytes) -> Unit {
  for b in bytes {
    out.push(b)
  }
}

///|
fn pack_metadata(raw : Array[Byte]) -> Bytes {
  let out : Array[Byte] = []
  let mut at = 0
  while at < raw.length() {
    let size = Int::min(8192, raw.length() - at)
    put16(out, size | 0x8000)
    for i in at..<(at + size) {
      out.push(raw[i])
    }
    at += size
  }
  Bytes::from_array(out)
}

///|
fn metadata_ref(raw_offset : Int) -> UInt64 {
  ((raw_offset / 8192 * 8194).to_uint64() << 16) |
  (raw_offset % 8192).to_uint64()
}

///|
fn canonical_parts(path : String) -> Array[String] raise SquashError {
  guard path.has_prefix("/") && path != "/" else {
    raise Invalid(0, "build paths must be absolute non-root paths")
  }
  let parts = path.split("/").map(p => p.to_owned()).to_array()
  guard parts.length() <= 129 else { raise Limit("build path depth") }
  for i in 1..<parts.length() {
    let b = @utf8.encode(parts[i])
    guard b.length() > 0 &&
      b.length() <= 256 &&
      b != b"." &&
      b != b".." &&
      !b.iter().any(c => c == 0) else {
      raise Invalid(0, "invalid build path component")
    }
  }
  parts
}

///|
/// Deterministic SquashFS 4 construction. Metadata blocks are deliberately
/// stored raw for stable inode references; data and fragments may be compressed.
pub fn build_image(
  entries : Array[BuildEntry],
  block_size? : Int = 131072,
  created? : UInt = 0U,
  attributes? : Map[String, BuildMetadata] = Map([]),
  compression? : Int = 1,
  encode? : ((Int, Bytes) -> Bytes raise SquashError)? = None,
  fragments? : Bool = true,
  exportable? : Bool = true,
) -> Bytes raise SquashError {
  guard block_size >= 4096 &&
    block_size <= 1048576 &&
    (block_size & (block_size - 1)) == 0 else {
    raise Invalid(0, "invalid block size")
  }
  guard compression >= 1 && compression <= 6 else {
    raise Unsupported("compressor ID")
  }
  guard entries.length() <= 10000 else { raise Limit("build entries") }
  let inputs : Map[String, BuildEntry] = Map([])
  inputs["/"] = { path: "/", mode: 493, content: Folder, }
  let explicit : Map[String, Bool] = Map([])
  let mut total_data = 0
  for e in entries {
    guard e.mode >= 0 && e.mode <= 4095 else {
      raise Invalid(0, "mode exceeds permission bits")
    }
    guard !explicit.contains(e.path) else {
      raise Invalid(0, "duplicate build path")
    }
    explicit[e.path] = true
    let parts = if e.path == "/" {
      guard e.content is Folder else {
        raise Invalid(0, "root must be a directory")
      }
      [""]
    } else {
      canonical_parts(e.path)
    }
    match e.content {
      Regular(b) => {
        guard b.length() <= 134217728 - total_data else {
          raise Limit("build data exceeds 128 MiB")
        }
        total_data += b.length()
      }
      Symbolic(b) => {
        guard b.length() > 0 &&
          b.length() <= 65536 &&
          !b.iter().any(c => c == 0) else {
          raise Invalid(0, "symlink target")
        }
      }
      Hardlink(path) => ignore(canonical_parts(path))
      _ => ()
    }
    inputs[e.path] = e
    let mut parent = ""
    for i in 1..<(parts.length() - 1) {
      parent = parent + "/" + parts[i]
      if !inputs.contains(parent) {
        inputs[parent] = { path: parent, mode: 493, content: Folder, }
      }
    }
  }
  guard inputs.length() <= 20000 else { raise Limit("expanded tree") }
  for path in attributes.keys() {
    guard inputs.contains(path) else {
      raise Invalid(0, "metadata path not in tree")
    }
  }
  let paths = inputs.keys().to_array()
  paths.sort_by((a, b) => @utf8.encode(a).lexical_compare(@utf8.encode(b)))
  let nodes : Array[BuildNode] = []
  let positions : Map[String, Int] = Map([])
  for path in paths {
    let input = inputs[path]
    let parts = path.split("/").map(p => p.to_owned()).to_array()
    positions[path] = nodes.length()
    nodes.push({
      path,
      name: @utf8.encode(parts[parts.length() - 1]),
      mode: input.mode,
      content: input.content,
      parent: 0,
      children: [],
      raw_inode: 0,
      raw_dir: 0,
      dir_size: 0,
      data_start: 0,
      blocks: [],
      sparse: 0,
      target: nodes.length(),
      number: 0,
      links: 1,
      fragment: 0xffffffffU,
      fragment_offset: 0,
      xattr: 0xffffffffU,
    })
  }
  let unique : Array[Int] = []
  for i, node in nodes {
    if node.content is Hardlink(_) {
      continue
    }
    node.number = unique.length() + 1
    unique.push(i)
  }
  for i, node in nodes {
    if node.content is Hardlink(_) {
      guard !attributes.contains(node.path) else {
        raise Invalid(0, "hard-link metadata belongs on target")
      }
      let seen : Map[Int, Bool] = Map([])
      let mut target = i
      while nodes[target].content is Hardlink(path) {
        guard !seen.contains(target) else {
          raise Invalid(0, "hard-link cycle")
        }
        seen[target] = true
        guard positions.get(path) is Some(next) else {
          raise Invalid(0, "missing hard-link target")
        }
        target = next
      }
      guard !(nodes[target].content is Folder) else {
        raise Invalid(0, "directory hard link")
      }
      node.target = target
      node.number = nodes[target].number
      nodes[target].links += 1
    }
    if i > 0 {
      let parts = node.path.split("/").map(p => p.to_owned()).to_array()
      ignore(parts.pop())
      let parent_path = if parts.length() == 1 { "/" } else { parts.join("/") }
      let parent = positions[parent_path]
      guard nodes[parent].content is Folder else {
        raise Invalid(0, "build parent is not a directory")
      }
      node.parent = parent
      nodes[parent].children.push(i)
    }
  }
  let default_attr : BuildMetadata = {
    uid: 0U,
    gid: 0U,
    mtime: created,
    xattrs: [],
  }
  let ids : Array[UInt] = []
  let id_map : Map[UInt, Int] = Map([])
  let xattr_data : Array[Byte] = []
  let xattr_ids : Array[Byte] = []
  for i in unique {
    let node = nodes[i]
    let attr = attributes.get(node.path).unwrap_or(default_attr)
    for id in [attr.uid, attr.gid] {
      if !id_map.contains(id) {
        id_map[id] = ids.length()
        ids.push(id)
      }
    }
    if attr.xattrs.length() > 0 {
      guard attr.xattrs.length() <= 65536 else { raise Limit("xattr count") }
      node.xattr = (xattr_ids.length() / 16).reinterpret_as_uint()
      put64(xattr_ids, metadata_ref(xattr_data.length()))
      put32(xattr_ids, attr.xattrs.length().reinterpret_as_uint())
      let sorted = attr.xattrs.copy()
      sorted.sort_by((a, b) => a.name.lexical_compare(b.name))
      let seen : Map[Bytes, Bool] = Map([])
      let mut total = 0
      for a in sorted {
        guard a.name.length() <= 255 &&
          !a.name.iter().any(c => c == 0) &&
          !seen.contains(a.name) else {
          raise Invalid(0, "duplicate or invalid xattr name")
        }
        seen[a.name] = true
        let (kind, prefix) = if a.name.has_prefix(b"user.") {
          (0, 5)
        } else if a.name.has_prefix(b"trusted.") {
          (1, 8)
        } else if a.name.has_prefix(b"security.") {
          (2, 9)
        } else {
          raise Unsupported("xattr namespace")
        }
        guard a.name.length() > prefix && a.value.length() <= 65536 else {
          raise Limit("xattr name/value")
        }
        guard xattr_data.length() <=
          16777216 - a.name.length() - a.value.length() - 8 else {
          raise Limit("build xattr total")
        }
        put16(xattr_data, kind)
        put16(xattr_data, a.name.length() - prefix)
        append_bytes(xattr_data, a.name[prefix:].to_owned())
        put32(xattr_data, a.value.length().reinterpret_as_uint())
        append_bytes(xattr_data, a.value)
        total += a.name.length() + 1 + a.value.length()
      }
      put32(xattr_ids, total.reinterpret_as_uint())
    }
  }
  guard ids.length() <= 65535 else { raise Limit("UID/GID table") }
  let output : Array[Byte] = Array::make(96, 0)
  // LZ4 SquashFS requires a version/options metadata block.
  if compression == 5 {
    append_bytes(output, pack_metadata([1, 0, 0, 0, 0, 0, 0, 0]))
  }
  let fragments_data : Array[Bytes] = []
  let mut tail : Array[Byte] = []
  let mut inode_size = 0
  for i in unique {
    let node = nodes[i]
    node.raw_inode = inode_size
    match node.content {
      Folder => inode_size += 40
      Symbolic(b) => inode_size += 28 + b.length()
      BlockDevice(_) | CharDevice(_) => inode_size += 28
      Fifo | Socket => inode_size += 24
      Hardlink(_) => raise Invalid(0, "unresolved link")
      Regular(b) => {
        node.data_start = output.length()
        let mut at = 0
        while at < b.length() {
          let size = Int::min(block_size, b.length() - at)
          let chunk = region(b, at, size)
          if fragments && size < block_size {
            if tail.length() + size > block_size {
              fragments_data.push(Bytes::from_array(tail))
              tail = []
            }
            node.fragment = fragments_data.length().reinterpret_as_uint()
            node.fragment_offset = tail.length()
            append_bytes(tail, chunk)
          } else if chunk.iter().all(c => c == 0) {
            node.blocks.push(0U)
            node.sparse += size
          } else {
            node.blocks.push(store_block(output, chunk, compression, encode))
          }
          at += size
        }
        inode_size += 56 + node.blocks.length() * 4
      }
    }
  }
  if tail.length() > 0 {
    fragments_data.push(Bytes::from_array(tail))
  }
  let fragment_records : Array[Byte] = []
  for data in fragments_data {
    let start = output.length()
    let descriptor = store_block(output, data, compression, encode)
    put64(fragment_records, start.to_uint64())
    put32(fragment_records, descriptor)
    put32(fragment_records, 0U)
  }
  let directories : Array[Byte] = []
  for i in unique {
    let node = nodes[i]
    if node.content is Folder {
      node.raw_dir = directories.length()
      for child_index in node.children {
        let entry = nodes[child_index]
        let child = nodes[entry.target]
        let reference = metadata_ref(child.raw_inode)
        put32(directories, 0U)
        put32(directories, (reference >> 16).to_uint())
        put32(directories, child.number.reinterpret_as_uint())
        put16(directories, (reference & 0xffffUL).to_int())
        put16(directories, 0)
        put16(directories, build_kind(child.content))
        put16(directories, entry.name.length() - 1)
        append_bytes(directories, entry.name)
      }
      node.dir_size = directories.length() - node.raw_dir
    }
  }
  let inodes : Array[Byte] = []
  let exports : Array[Byte] = []
  for i in unique {
    let node = nodes[i]
    let attr = attributes.get(node.path).unwrap_or(default_attr)
    put64(exports, metadata_ref(node.raw_inode))
    put16(inodes, build_kind(node.content) + 7)
    put16(inodes, node.mode)
    put16(inodes, id_map[attr.uid])
    put16(inodes, id_map[attr.gid])
    put32(inodes, attr.mtime)
    put32(inodes, node.number.reinterpret_as_uint())
    match node.content {
      Folder => {
        let child_dirs = node.children
          .filter(j => nodes[j].content is Folder)
          .length()
        let reference = metadata_ref(node.raw_dir)
        put32(inodes, (2 + child_dirs).reinterpret_as_uint())
        put32(inodes, (node.dir_size + 3).reinterpret_as_uint())
        put32(inodes, (reference >> 16).to_uint())
        put32(
          inodes,
          (if i == 0 { unique.length() + 1 } else { nodes[node.parent].number }).reinterpret_as_uint(),
        )
        put16(inodes, 0)
        put16(inodes, (reference & 0xffffUL).to_int())
        put32(inodes, node.xattr)
      }
      Regular(b) => {
        put64(inodes, node.data_start.to_uint64())
        put64(inodes, b.length().to_uint64())
        put64(inodes, node.sparse.to_uint64())
        put32(inodes, node.links.reinterpret_as_uint())
        put32(inodes, node.fragment)
        put32(inodes, node.fragment_offset.reinterpret_as_uint())
        put32(inodes, node.xattr)
        for descriptor in node.blocks {
          put32(inodes, descriptor)
        }
      }
      Symbolic(b) => {
        put32(inodes, node.links.reinterpret_as_uint())
        put32(inodes, b.length().reinterpret_as_uint())
        append_bytes(inodes, b)
        put32(inodes, node.xattr)
      }
      BlockDevice(dev) | CharDevice(dev) => {
        put32(inodes, node.links.reinterpret_as_uint())
        put32(inodes, dev)
        put32(inodes, node.xattr)
      }
      Fifo | Socket => {
        put32(inodes, node.links.reinterpret_as_uint())
        put32(inodes, node.xattr)
      }
      Hardlink(_) => raise Invalid(0, "unresolved link")
    }
  }
  let inode_table = output.length()
  append_bytes(output, pack_metadata(inodes))
  let directory_table = output.length()
  append_bytes(output, pack_metadata(directories))
  let fragment_table = if fragments_data.length() > 0 {
    write_index(output, fragment_records).to_uint64()
  } else {
    0xffffffffffffffffUL
  }
  let export_table = if exportable {
    write_index(output, exports).to_uint64()
  } else {
    0xffffffffffffffffUL
  }
  let raw_ids : Array[Byte] = []
  for id in ids {
    put32(raw_ids, id)
  }
  let id_table = write_index(output, raw_ids)
  let xattr_table = if xattr_ids.length() > 0 {
    let start = output.length()
    append_bytes(output, pack_metadata(xattr_data))
    let id_start = output.length()
    append_bytes(output, pack_metadata(xattr_ids))
    let table = output.length()
    put64(output, start.to_uint64())
    put32(output, (xattr_ids.length() / 16).reinterpret_as_uint())
    put32(output, 0U)
    for i in 0..<((xattr_ids.length() + 8191) / 8192) {
      put64(output, (id_start + i * 8194).to_uint64())
    }
    table.to_uint64()
  } else {
    0xffffffffffffffffUL
  }
  let header : Array[Byte] = []
  put32(header, 0x73717368U)
  put32(header, unique.length().reinterpret_as_uint())
  put32(header, created)
  put32(header, block_size.reinterpret_as_uint())
  put32(header, fragments_data.length().reinterpret_as_uint())
  put16(header, compression)
  let mut log = 0
  let mut shifted = block_size
  while shifted > 1 {
    log += 1
    shifted = shifted >> 1
  }
  put16(header, log)
  let flags = 0x901 |
    (if encode is None { 0xA } else { 0 }) |
    (if !fragments { 0x10 } else { 0x20 }) |
    (if exportable { 0x80 } else { 0 }) |
    (if xattr_ids.length() == 0 { 0x200 } else { 0 }) |
    (if compression == 5 { 0x400 } else { 0 })
  put16(header, flags)
  put16(header, ids.length())
  put16(header, 4)
  put16(header, 0)
  put64(header, metadata_ref(nodes[0].raw_inode))
  put64(header, output.length().to_uint64())
  put64(header, id_table.to_uint64())
  put64(header, xattr_table)
  put64(header, inode_table.to_uint64())
  put64(header, directory_table.to_uint64())
  put64(header, fragment_table)
  put64(header, export_table)
  for i in 0..<96 {
    output[i] = header[i]
  }
  Bytes::from_array(output)
}
