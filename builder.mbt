///|
pub(all) enum BuildContent {
  Folder
  Regular(Bytes)
  External(Int)
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
  mut reference : UInt64
  mut dir_reference : UInt64
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
    Regular(_) | External(_) | Hardlink(_) => 2
    Symbolic(_) => 3
    BlockDevice(_) => 4
    CharDevice(_) => 5
    Fifo => 6
    Socket => 7
  }
}

///|
fn store_block(
  out : BuildOutput,
  data : Bytes,
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> UInt raise SquashError {
  if encode is Some(compress) {
    let packed = compress(compression, data)
    if packed.length() > 0 && packed.length() < data.length() {
      out.append(packed)
      return packed.length().reinterpret_as_uint()
    }
  }
  out.append(data)
  data.length().reinterpret_as_uint() | 0x1000000U
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
/// Deterministic SquashFS 4 construction with child-first compressed metadata.
fn build_internal(
  entries : Array[BuildEntry],
  output : BuildOutput,
  read : ((String, Int, Int) -> Bytes raise SquashError)?,
  max_data : UInt64,
  block_size? : Int = 131072,
  created? : UInt = 0U,
  attributes? : Map[String, BuildMetadata] = Map([]),
  compression? : Int = 1,
  encode? : ((Int, Bytes) -> Bytes raise SquashError)? = None,
  fragments? : Bool = true,
  exportable? : Bool = true,
  metadata_compression? : Bool = true,
) -> Superblock raise SquashError {
  guard block_size >= 4096 &&
    block_size <= 1048576 &&
    (block_size & (block_size - 1)) == 0 else {
    raise Invalid(0, "invalid block size")
  }
  guard compression >= 1 && compression <= 6 else {
    raise Unsupported("compressor ID")
  }
  guard entries.length() <= 10000 else { raise Limit("build entries") }
  let meta_encode = if metadata_compression { encode } else { None }
  let inputs : Map[String, BuildEntry] = Map([])
  inputs["/"] = { path: "/", mode: 493, content: Folder, }
  let explicit : Map[String, Bool] = Map([])
  let mut total_data = 0UL
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
      Regular(_) | External(_) => {
        let size = payload_size(e.content)
        guard size >= 0 &&
          size.to_uint64() <= max_data &&
          total_data <= max_data - size.to_uint64() else {
          raise Limit("build payload budget")
        }
        if e.content is External(_) {
          guard read is Some(_) else {
            raise Invalid(0, "External entries require build_to")
          }
        }
        total_data += size.to_uint64()
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
      reference: 0UL,
      dir_reference: 0UL,
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
      put64(xattr_ids, xattr_data.length().to_uint64())
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
  output.append(Bytes::make(96, 0))
  // LZ4 SquashFS requires a version/options metadata block.
  if compression == 5 {
    output.append(pack_metadata([1, 0, 0, 0, 0, 0, 0, 0]))
  }
  let fragment_records : Array[Byte] = []
  let mut tail : Array[Byte] = []
  for i in unique {
    let node = nodes[i]
    match node.content {
      Folder | Symbolic(_) | BlockDevice(_) | CharDevice(_) | Fifo | Socket =>
        ()
      Hardlink(_) => raise Invalid(0, "unresolved link")
      Regular(_) | External(_) => {
        let length = payload_size(node.content)
        node.data_start = output.length()
        let mut at = 0
        while at < length {
          let size = Int::min(block_size, length - at)
          let chunk = match node.content {
            Regular(b) => region(b, at, size)
            External(_) =>
              match read {
                Some(read) => read(node.path, at, size)
                None => raise Invalid(at, "missing source reader")
              }
            _ => raise Invalid(at, "not a regular payload")
          }
          guard chunk.length() == size else {
            raise Invalid(at, "source returned a short block")
          }
          if fragments && size < block_size {
            if tail.length() + size > block_size {
              flush_fragment(
                output, tail, fragment_records, compression, encode,
              )
              tail = []
            }
            node.fragment = (fragment_records.length() / 16).reinterpret_as_uint()
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
      }
    }
  }
  flush_fragment(output, tail, fragment_records, compression, encode)
  let fragment_count = fragment_records.length() / 16
  let directory_stream = metadata_writer(compression, meta_encode)
  let inode_stream = metadata_writer(compression, meta_encode)
  let emission : Array[Int] = unique.filter(i => !(nodes[i].content is Folder))
  for j in 0..<unique.length() {
    let i = unique[unique.length() - 1 - j]
    if nodes[i].content is Folder {
      emission.push(i)
    }
  }
  for i in emission {
    let node = nodes[i]
    if node.content is Folder {
      let directories : Array[Byte] = []
      node.dir_reference = directory_stream.position()
      for child_index in node.children {
        let entry = nodes[child_index]
        let child = nodes[entry.target]
        let reference = child.reference
        put32(directories, 0U)
        put32(directories, (reference >> 16).to_uint())
        put32(directories, child.number.reinterpret_as_uint())
        put16(directories, (reference & 0xffffUL).to_int())
        put16(directories, 0)
        put16(directories, build_kind(child.content))
        put16(directories, entry.name.length() - 1)
        append_bytes(directories, entry.name)
      }
      node.dir_size = directories.length()
      directory_stream.append(directories)
    }
    let inodes : Array[Byte] = []
    node.reference = inode_stream.position()
    let attr = attributes.get(node.path).unwrap_or(default_attr)
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
        let reference = node.dir_reference
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
      Regular(_) | External(_) => {
        put64(inodes, node.data_start.to_uint64())
        put64(inodes, payload_size(node.content).to_uint64())
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
    inode_stream.append(inodes)
  }
  inode_stream.flush()
  directory_stream.flush()
  let exports : Array[Byte] = []
  for i in unique {
    put64(exports, nodes[i].reference)
  }
  let inode_table = output.length()
  output.append(Bytes::from_array(inode_stream.stored))
  let directory_table = output.length()
  output.append(Bytes::from_array(directory_stream.stored))
  let fragment_table = if fragment_count > 0 {
    write_compressed_index(output, fragment_records, compression, meta_encode).to_uint64()
  } else {
    0xffffffffffffffffUL
  }
  let export_table = if exportable {
    write_compressed_index(output, exports, compression, meta_encode).to_uint64()
  } else {
    0xffffffffffffffffUL
  }
  let raw_ids : Array[Byte] = []
  for id in ids {
    put32(raw_ids, id)
  }
  let id_table = write_compressed_index(
    output, raw_ids, compression, meta_encode,
  )
  let xattr_table = if xattr_ids.length() > 0 {
    let values = compressed_metadata(xattr_data, compression, meta_encode)
    let raw_xattr_ids = Bytes::from_array(xattr_ids)
    for i in 0..<(xattr_ids.length() / 16) {
      let raw = index(u64(raw_xattr_ids, i * 16), i * 16)
      let reference = values.mapped_reference(raw)
      for j in 0..<8 {
        xattr_ids[i * 16 + j] = ((reference >> (j * 8)) & 255UL).to_byte()
      }
    }
    let records = compressed_metadata(xattr_ids, compression, meta_encode)
    let start = output.length()
    output.append(Bytes::from_array(values.stored))
    let id_start = output.length()
    output.append(Bytes::from_array(records.stored))
    let table = output.length()
    output.uint64(start.to_uint64())
    output.uint((xattr_ids.length() / 16).reinterpret_as_uint())
    output.uint(0U)
    for offset in records.starts {
      output.uint64((id_start + offset).to_uint64())
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
  put32(header, fragment_count.reinterpret_as_uint())
  put16(header, compression)
  let mut log = 0
  let mut shifted = block_size
  while shifted > 1 {
    log += 1
    shifted = shifted >> 1
  }
  put16(header, log)
  let flags = (if meta_encode is None { 0x901 } else { 0 }) |
    (if encode is None { 0xA } else { 0 }) |
    (if !fragments { 0x10 } else { 0x20 }) |
    (if exportable { 0x80 } else { 0 }) |
    (if xattr_ids.length() == 0 { 0x200 } else { 0 }) |
    (if compression == 5 { 0x400 } else { 0 })
  put16(header, flags)
  put16(header, ids.length())
  put16(header, 4)
  put16(header, 0)
  put64(header, nodes[0].reference)
  put64(header, output.length().to_uint64())
  put64(header, id_table.to_uint64())
  put64(header, xattr_table)
  put64(header, inode_table.to_uint64())
  put64(header, directory_table.to_uint64())
  put64(header, fragment_table)
  put64(header, export_table)
  let bytes = Bytes::from_array(header)
  (output.write)(0, bytes)
  parse_superblock(bytes, output.length())
}
