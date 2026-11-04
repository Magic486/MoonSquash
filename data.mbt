///|
fn Image::data_block(
  self : Image,
  at : Int,
  descriptor : UInt,
  limit : Int,
) -> Bytes raise SquashError {
  let key = "\{at}:\{descriptor}:\{limit}"
  if self.data_cache.get(key) is Some(bytes) {
    return bytes
  }
  guard (descriptor & 0xfe000000U) == 0U else {
    raise Invalid(at, "reserved data block bits")
  }
  let size = (descriptor & 0xffffffU).reinterpret_as_int()
  guard size > 0 && size <= self.superblock.block_size else {
    raise Invalid(at, "invalid stored data size")
  }
  guard at >= 96 &&
    at <= self.superblock.inode_table &&
    size <= self.superblock.inode_table - at else {
    raise Invalid(at, "data overlaps inode table")
  }
  let b = self.range(at, size)
  let decoded = if (descriptor & 0x1000000U) != 0U {
    b
  } else {
    (self.decode)(self.superblock.compression, b, limit)
  }
  guard decoded.length() > 0 && decoded.length() <= limit else {
    raise Invalid(at, "invalid decoded data length")
  }
  if self.data_cache.length() >= 16 {
    self.data_cache.clear()
  }
  self.data_cache[key] = decoded
  decoded
}

///|
pub fn Image::read_file(
  self : Image,
  file : Inode,
  max_bytes? : Int = 67108864,
) -> Bytes raise SquashError {
  guard file.content is File(start, size, fragment, fragment_offset, blocks) else {
    raise Invalid(file.number, "not a regular file")
  }
  guard max_bytes >= 0 && size <= max_bytes else {
    raise Limit("file output exceeds max_bytes")
  }
  let out : Array[Byte] = []
  let mut at = start
  for descriptor in blocks {
    let expected = Int::min(self.superblock.block_size, size - out.length())
    if descriptor == 0U {
      for _ in 0..<expected {
        out.push(0)
      }
    } else {
      let b = self.data_block(at, descriptor, expected)
      guard b.length() == expected else {
        raise Invalid(at, "file data length mismatch")
      }
      for byte in b {
        out.push(byte)
      }
      at += (descriptor & 0xffffffU).reinterpret_as_int()
    }
  }
  if fragment != 0xffffffffU {
    guard fragment.to_uint64() < self.superblock.fragments.to_uint64() else {
      raise Invalid(80, "fragment ID out of range")
    }
    let id = fragment.reinterpret_as_int()
    let table = self.superblock.fragment_table
    let pointer = self.pointer(table + id / 512 * 8)
    let record = self.metadata(pointer, id % 512 * 16, 16)
    let fragment_at = index(u64(record, 0), pointer)
    let data = self.data_block(
      fragment_at,
      u32(record, 8),
      self.superblock.block_size,
    )
    let tail = region(data, fragment_offset, size - out.length())
    for byte in tail {
      out.push(byte)
    }
  }
  guard out.length() == size else {
    raise Invalid(at, "file output length mismatch")
  }
  Bytes::from_array(out)
}
