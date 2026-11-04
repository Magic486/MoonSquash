///|
pub(all) enum BuildContent {
  Folder
  Regular(Bytes)
  Symbolic(Bytes)
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

///| Construct a deterministic uncompressed SquashFS 4 image. Owners are root,

///| time is caller supplied, folders are inserted automatically. No fragments,

///|
/// xattrs, export table or hard-link deduplication are emitted by this profile.
pub fn build_image(
  entries : Array[BuildEntry],
  block_size? : Int = 131072,
  created? : UInt = 0U,
) -> Bytes raise SquashError {
  guard block_size >= 4096 &&
    block_size <= 1048576 &&
    (block_size & (block_size - 1)) == 0 else {
    raise Invalid(0, "invalid build block size")
  }
  guard entries.length() <= 10000 else { raise Limit("build entry count") }
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
    let parts = canonical_parts(e.path)
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
          raise Invalid(0, "invalid symlink target")
        }
      }
      Folder => ()
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
  guard inputs.length() <= 20000 else { raise Limit("build expanded tree") }
  let paths = inputs.keys().to_array()
  paths.sort_by((a, b) => @utf8.encode(a).lexical_compare(@utf8.encode(b)))
  let nodes : Array[BuildNode] = []
  let positions : Map[String, Int] = Map([])
  for path in paths {
    let input = inputs[path]
    let parts = path.split("/").map(p => p.to_owned()).to_array()
    let name = @utf8.encode(parts[parts.length() - 1])
    positions[path] = nodes.length()
    nodes.push({
      path,
      name,
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
    })
  }
  for i in 1..<nodes.length() {
    let parts = nodes[i].path.split("/").map(p => p.to_owned()).to_array()
    ignore(parts.pop())
    let parent_path = if parts.length() == 1 { "/" } else { parts.join("/") }
    let parent = positions[parent_path]
    guard nodes[parent].content is Folder else {
      raise Invalid(0, "build parent is not a directory")
    }
    nodes[i].parent = parent
    nodes[parent].children.push(i)
  }
  let output : Array[Byte] = Array::make(96, 0)
  let mut inode_size = 0
  for node in nodes {
    node.raw_inode = inode_size
    match node.content {
      Folder => inode_size += 40
      Symbolic(b) => inode_size += 24 + b.length()
      Regular(b) => {
        node.data_start = output.length()
        let mut at = 0
        while at < b.length() {
          let size = Int::min(block_size, b.length() - at)
          let chunk = region(b, at, size)
          if chunk.iter().all(c => c == 0) {
            node.blocks.push(0U)
            node.sparse += size
          } else {
            node.blocks.push(size.reinterpret_as_uint() | 0x1000000U)
            append_bytes(output, chunk)
          }
          at += size
        }
        inode_size += 56 + node.blocks.length() * 4
      }
    }
  }
  let directories : Array[Byte] = []
  for node in nodes {
    if node.content is Folder {
      node.raw_dir = directories.length()
      for child_index in node.children {
        let child = nodes[child_index]
        let reference = metadata_ref(child.raw_inode)
        put32(directories, 0U) // One entry per directory group.
        put32(directories, (reference >> 16).to_uint())
        put32(directories, (child_index + 1).reinterpret_as_uint())
        put16(directories, (reference & 0xffffUL).to_int())
        put16(directories, 0)
        put16(
          directories,
          match child.content {
            Folder => 1
            Regular(_) => 2
            Symbolic(_) => 3
          },
        )
        put16(directories, child.name.length() - 1)
        append_bytes(directories, child.name)
      }
      node.dir_size = directories.length() - node.raw_dir
    }
  }
  let inodes : Array[Byte] = []
  for i, node in nodes {
    put16(
      inodes,
      match node.content {
        Folder => 8
        Regular(_) => 9
        Symbolic(_) => 3
      },
    )
    put16(inodes, node.mode)
    put16(inodes, 0)
    put16(inodes, 0)
    put32(inodes, created)
    put32(inodes, (i + 1).reinterpret_as_uint())
    match node.content {
      Folder => {
        let children = node.children
          .filter(j => nodes[j].content is Folder)
          .length()
        let reference = metadata_ref(node.raw_dir)
        put32(inodes, (2 + children).reinterpret_as_uint())
        put32(inodes, (node.dir_size + 3).reinterpret_as_uint())
        put32(inodes, (reference >> 16).to_uint())
        put32(
          inodes,
          (if i == 0 { nodes.length() + 1 } else { node.parent + 1 }).reinterpret_as_uint(),
        )
        put16(inodes, 0)
        put16(inodes, (reference & 0xffffUL).to_int())
        put32(inodes, 0xffffffffU)
      }
      Regular(b) => {
        put64(inodes, node.data_start.to_uint64())
        put64(inodes, b.length().to_uint64())
        put64(inodes, node.sparse.to_uint64())
        put32(inodes, 1U)
        put32(inodes, 0xffffffffU)
        put32(inodes, 0U)
        put32(inodes, 0xffffffffU)
        for descriptor in node.blocks {
          put32(inodes, descriptor)
        }
      }
      Symbolic(b) => {
        put32(inodes, 1U)
        put32(inodes, b.length().reinterpret_as_uint())
        append_bytes(inodes, b)
      }
    }
  }
  let inode_table = output.length()
  append_bytes(output, pack_metadata(inodes))
  let directory_table = output.length()
  append_bytes(output, pack_metadata(directories))
  let id_block = output.length()
  append_bytes(output, pack_metadata([0, 0, 0, 0]))
  let id_table = output.length()
  put64(output, id_block.to_uint64())
  let used = output.length()
  let header : Array[Byte] = []
  put32(header, 0x73717368U)
  put32(header, nodes.length().reinterpret_as_uint())
  put32(header, created)
  put32(header, block_size.reinterpret_as_uint())
  put32(header, 0U)
  put16(header, 1)
  let mut log = 0
  let mut shifted = block_size
  while shifted > 1 {
    log += 1
    shifted = shifted >> 1
  }
  put16(header, log)
  put16(header, 0xA1B) // No inode/data/fragment compression, no fragments/xattrs, raw IDs.
  put16(header, 1)
  put16(header, 4)
  put16(header, 0)
  put64(header, 0UL)
  put64(header, used.to_uint64())
  put64(header, id_table.to_uint64())
  put64(header, 0xffffffffffffffffUL)
  put64(header, inode_table.to_uint64())
  put64(header, directory_table.to_uint64())
  put64(header, 0xffffffffffffffffUL)
  put64(header, 0xffffffffffffffffUL)
  for i in 0..<96 {
    output[i] = header[i]
  }
  Bytes::from_array(output)
}
