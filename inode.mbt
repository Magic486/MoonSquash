///|
pub fn Image::inode(
  self : Image,
  reference : UInt64,
) -> Inode raise SquashError {
  let relative = index(reference >> 16, 32)
  guard relative < self.superblock.directory_table - self.superblock.inode_table else {
    raise Invalid(relative, "inode reference outside inode table")
  }
  let block = self.superblock.inode_table + relative
  let offset = (reference & 0xffffUL).to_int()
  let base = self.metadata(block, offset, 16)
  let kind = u16(base, 0)
  let number = index(u32(base, 12).to_uint64(), block)
  guard number > 0 && number <= self.superblock.inodes else {
    raise Invalid(block, "inode number out of range")
  }
  let uid = self.identity(u16(base, 4))
  let gid = self.identity(u16(base, 6))
  let mut links = 1
  let mut xattr = 0xffffffffU
  let mut parent = 0
  let content = match kind {
    1 | 8 => {
      let long = kind == 8
      let b = self.metadata(block, offset, if long { 40 } else { 32 })
      let start = index(u32(b, if long { 24 } else { 16 }).to_uint64(), block)
      let size = if long {
        index(u32(b, 20).to_uint64(), block)
      } else {
        u16(b, 24)
      }
      let off = u16(b, if long { 34 } else { 26 })
      links = index(u32(b, if long { 16 } else { 20 }).to_uint64(), block)
      if long {
        xattr = u32(b, 36)
      }
      parent = index(u32(b, 28).to_uint64(), block)
      guard size >= 3 &&
        start <= self.superblock.bytes_used - self.superblock.directory_table else {
        raise Invalid(block, "invalid directory")
      }
      Directory(self.superblock.directory_table + start, off, size - 3)
    }
    2 | 9 => {
      let long = kind == 9
      let head = if long { 56 } else { 32 }
      let b = self.metadata(block, offset, head)
      let start = if long {
        index(u64(b, 16), block)
      } else {
        index(u32(b, 16).to_uint64(), block)
      }
      let size = if long {
        index(u64(b, 24), block)
      } else {
        index(u32(b, 28).to_uint64(), block)
      }
      let fragment = u32(b, if long { 44 } else { 20 })
      let fragment_offset = index(
        u32(b, if long { 48 } else { 24 }).to_uint64(),
        block,
      )
      if long {
        links = index(u32(b, 40).to_uint64(), block)
        xattr = u32(b, 52)
      }
      let bs = self.superblock.block_size
      let count = size / bs +
        (if fragment == 0xffffffffU && size % bs != 0 { 1 } else { 0 })
      guard count <= 1048576 else { raise Limit("file block list") }
      let all = self.metadata(block, offset, head + count * 4)
      let blocks = Array::makei(count, i => u32(all, head + i * 4))
      File(start, size, fragment, fragment_offset, blocks)
    }
    3 | 10 => {
      let b = self.metadata(block, offset, 24)
      links = index(u32(b, 16).to_uint64(), block)
      let len = index(u32(b, 20).to_uint64(), block)
      guard len > 0 && len <= 65536 else { raise Limit("symlink length") }
      if kind == 10 {
        xattr = u32(self.metadata(block, offset, 28 + len), 24 + len)
      }
      Symlink(region(self.metadata(block, offset, 24 + len), 24, len))
    }
    4 | 5 | 11 | 12 => {
      let b = self.metadata(block, offset, 24)
      links = index(u32(b, 16).to_uint64(), block)
      if kind > 7 {
        xattr = u32(self.metadata(block, offset, 28), 24)
      }
      Device(u32(b, 20))
    }
    6 | 7 | 13 | 14 => {
      let b = self.metadata(block, offset, 20)
      links = index(u32(b, 16).to_uint64(), block)
      if kind > 7 {
        xattr = u32(self.metadata(block, offset, 24), 20)
      }
      Special
    }
    _ => raise Invalid(block, "unknown inode type \{kind}")
  }
  {
    reference,
    number,
    kind,
    mode: u16(base, 2),
    uid,
    gid,
    mtime: u32(base, 8),
    links,
    xattr,
    parent,
    content,
  }
}

///|
pub fn Image::root(self : Image) -> Inode raise SquashError {
  self.inode(self.superblock.root)
}

///|
pub fn Image::entries(
  self : Image,
  dir : Inode,
) -> Array[DirEntry] raise SquashError {
  guard dir.content is Directory(block, offset, size) else {
    raise Invalid(dir.number, "not a directory")
  }
  let b = self.metadata(block, offset, size)
  let entries : Array[DirEntry] = []
  let names : Map[Bytes, Bool] = Map([])
  let mut pos = 0
  while pos < b.length() {
    let count_minus_one = u32(b, pos)
    guard count_minus_one <= 255U else {
      raise Invalid(pos, "directory group exceeds 256 entries")
    }
    let count = count_minus_one.reinterpret_as_int() + 1
    let start = u32(b, pos + 4)
    let base_number = index(u32(b, pos + 8).to_uint64(), pos)
    pos += 12
    for _ in 0..<count {
      let inode_offset = u16(b, pos)
      let delta = u16(b, pos + 2)
      let delta = if delta >= 32768 { delta - 65536 } else { delta }
      let kind = u16(b, pos + 4)
      let len = u16(b, pos + 6) + 1
      guard len <= 256 && inode_offset < 8192 && kind >= 1 && kind <= 7 else {
        raise Invalid(pos, "invalid directory entry")
      }
      let name = region(b, pos + 8, len)
      guard name != b"." &&
        name != b".." &&
        !name.iter().any(c => c == b'/' || c == 0) else {
        raise Invalid(pos, "unsafe directory name")
      }
      guard !names.contains(name) else {
        raise Invalid(pos, "duplicate directory name")
      }
      names[name] = true
      let number64 = base_number.to_int64() + delta.to_int64()
      guard number64 > 0L && number64 <= self.superblock.inodes.to_int64() else {
        raise Invalid(pos, "directory inode number")
      }
      entries.push({
        name,
        reference: (start.to_uint64() << 16) | inode_offset.to_uint64(),
        number: number64.to_int(),
        kind,
      })
      pos += 8 + len
    }
  }
  entries
}

///|
pub fn Image::lookup(self : Image, path : String) -> Inode raise SquashError {
  let mut node = self.root()
  if path == "/" {
    return node
  }
  guard path.has_prefix("/") else { raise Invalid(0, "path must be absolute") }
  let parts = path.split("/").to_array()
  for i in 1..<parts.length() {
    let part = parts[i].to_owned()
    guard part != "" && part != "." && part != ".." else {
      raise Invalid(0, "path must be canonical")
    }
    let name = @utf8.encode(part)
    let mut found : UInt64? = None
    for entry in self.entries(node) {
      if entry.name == name {
        found = Some(entry.reference)
      }
    }
    guard found is Some(reference) else {
      raise Invalid(0, "path not found: \{path}")
    }
    node = self.inode(reference)
  }
  node
}
