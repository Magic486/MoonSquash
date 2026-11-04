///|
fn region(data : Bytes, offset : Int, size : Int) -> Bytes raise SquashError {
  guard offset >= 0 &&
    size >= 0 &&
    offset <= data.length() &&
    size <= data.length() - offset else {
    raise Invalid(offset, "truncated range")
  }
  data[offset:offset + size].to_owned()
}

///|
fn u16(data : Bytes, at : Int) -> Int raise SquashError {
  let b = region(data, at, 2)
  b[0].to_int() | (b[1].to_int() << 8)
}

///|
fn u32(data : Bytes, at : Int) -> UInt raise SquashError {
  let b = region(data, at, 4)
  b[0].to_uint() |
  (b[1].to_uint() << 8) |
  (b[2].to_uint() << 16) |
  (b[3].to_uint() << 24)
}

///|
fn u64(data : Bytes, at : Int) -> UInt64 raise SquashError {
  u32(data, at).to_uint64() | (u32(data, at + 4).to_uint64() << 32)
}

///|
fn index(value : UInt64, at : Int) -> Int raise SquashError {
  guard value <= 2147483647UL else {
    raise Limit("offset/size exceeds in-memory profile at \{at}")
  }
  value.to_int()
}

///|
pub fn read_superblock(data : Bytes) -> Superblock raise SquashError {
  parse_superblock(data, data.length())
}

///|
fn parse_superblock(data : Bytes, length : Int) -> Superblock raise SquashError {
  ignore(region(data, 0, 96))
  guard u32(data, 0) == 0x73717368U else {
    raise Invalid(0, "not SquashFS little-endian magic")
  }
  guard u16(data, 28) == 4 && u16(data, 30) == 0 else {
    raise Unsupported("only SquashFS 4.0")
  }
  let block_size = index(u32(data, 12).to_uint64(), 12)
  let log = u16(data, 22)
  guard log >= 12 && log <= 20 && block_size == 1 << log else {
    raise Invalid(12, "block size/log mismatch")
  }
  let used = index(u64(data, 40), 40)
  guard used >= 96 && used <= length else {
    raise Invalid(40, "bytes_used exceeds image")
  }
  let inode_table = index(u64(data, 64), 64)
  let directory_table = index(u64(data, 72), 72)
  guard inode_table >= 96 &&
    inode_table < used &&
    directory_table >= inode_table &&
    directory_table <= used else {
    raise Invalid(64, "invalid metadata table order")
  }
  let count = index(u32(data, 4).to_uint64(), 4)
  let ids = u16(data, 26)
  let id_table = index(u64(data, 48), 48)
  guard count > 0 &&
    ids > 0 &&
    id_table >= directory_table &&
    id_table <= used - 8 else {
    raise Invalid(48, "invalid inode count or ID table")
  }
  let fragments = index(u32(data, 16).to_uint64(), 16)
  let fragment_raw = u64(data, 80)
  let fragment_table = if fragments == 0 { 0 } else { index(fragment_raw, 80) }
  guard fragments == 0 ||
    (fragment_table >= directory_table && fragment_table <= used - 8) else {
    raise Invalid(80, "invalid fragment index")
  }
  let compression = u16(data, 20)
  guard compression >= 1 && compression <= 6 else {
    raise Unsupported("compression ID \{compression}")
  }
  {
    inodes: count,
    created: u32(data, 8),
    block_size,
    fragments,
    compression,
    flags: u16(data, 24),
    ids,
    root: u64(data, 32),
    bytes_used: used,
    inode_table,
    directory_table,
    fragment_table,
    id_table,
    xattr_table: u64(data, 56),
    export_table: u64(data, 88),
  }
}

///|
pub fn open_image(
  bytes : Bytes,
  decode? : (Int, Bytes, Int) -> Bytes raise SquashError = no_decompressor,
) -> Image raise SquashError {
  let superblock = read_superblock(bytes)
  {
    read: (at, size) => region(bytes, at, size),
    superblock,
    decode,
    cache: Map([]),
    data_cache: Map([]),
    offsets: Map([]),
  }
}

///|
/// Open an immutable random-access source. The callback must return exactly
/// the requested bytes and keep the source stable for the Image lifetime.
pub fn open_source(
  length : Int,
  read : (Int, Int) -> Bytes raise SquashError,
  decode? : (Int, Bytes, Int) -> Bytes raise SquashError = no_decompressor,
) -> Image raise SquashError {
  let superblock = parse_superblock(read(0, 96), length)
  {
    read,
    superblock,
    decode,
    cache: Map([]),
    data_cache: Map([]),
    offsets: Map([]),
  }
}

///|
fn Image::range(self : Image, at : Int, size : Int) -> Bytes raise SquashError {
  guard at >= 0 &&
    size >= 0 &&
    at <= self.superblock.bytes_used &&
    size <= self.superblock.bytes_used - at else {
    raise Invalid(at, "image range")
  }
  let b = (self.read)(at, size)
  guard b.length() == size else { raise Invalid(at, "short source read") }
  b
}

///|
fn Image::pointer(self : Image, at : Int) -> Int raise SquashError {
  index(u64(self.range(at, 8), 0), at)
}

///|
fn Image::metadata_block(
  self : Image,
  at : Int,
) -> (Bytes, Int) raise SquashError {
  if self.cache.get(at) is Some(value) {
    return value
  }
  let word = u16(self.range(at, 2), 0)
  let size = word & 0x7fff
  guard size > 0 && size <= 8192 else {
    raise Invalid(at, "invalid metadata block size")
  }
  let stored = self.range(at + 2, size)
  let decoded = if (word & 0x8000) != 0 {
    stored
  } else {
    (self.decode)(self.superblock.compression, stored, 8192)
  }
  guard decoded.length() > 0 && decoded.length() <= 8192 else {
    raise Invalid(at, "invalid decoded metadata size")
  }
  let result = (decoded, at + 2 + size)
  if self.cache.length() >= 128 {
    self.cache.clear()
  }
  self.cache[at] = result
  result
}

///|
fn Image::metadata(
  self : Image,
  block : Int,
  offset : Int,
  size : Int,
) -> Bytes raise SquashError {
  guard offset >= 0 && offset < 8192 && size >= 0 && size <= 16777216 else {
    raise Limit("metadata read budget")
  }
  let out : Array[Byte] = []
  let mut at = block
  let mut pos = offset
  while out.length() < size {
    let (data, next) = self.metadata_block(at)
    guard pos < data.length() else {
      raise Invalid(at, "metadata offset outside block")
    }
    let take = Int::min(data.length() - pos, size - out.length())
    for i in pos..<(pos + take) {
      out.push(data[i])
    }
    at = next
    pos = 0
  }
  Bytes::from_array(out)
}

///|
fn Image::identity(self : Image, id : Int) -> UInt raise SquashError {
  guard id < self.superblock.ids else {
    raise Invalid(id, "UID/GID index out of range")
  }
  let pointer = self.pointer(self.superblock.id_table + id / 2048 * 8)
  u32(self.metadata(pointer, id % 2048 * 4, 4), 0)
}
