///|
/// Read a bounded file range without materializing preceding file blocks.
pub fn Image::read_range(
  self : Image,
  file : Inode,
  offset : Int,
  length : Int,
) -> Bytes raise SquashError {
  guard file.content is File(start, size, fragment, fragment_offset, blocks) else {
    raise Invalid(file.number, "not a file")
  }
  guard offset >= 0 &&
    length >= 0 &&
    length <= 16777216 &&
    offset <= size &&
    length <= size - offset else {
    raise Limit("file range bounds (maximum 16 MiB)")
  }
  let out : Array[Byte] = []
  let bs = self.superblock.block_size
  let offsets = match self.offsets.get(file.reference) {
    Some(value) => value
    None => {
      let result : Array[Int] = []
      let mut at = start
      for descriptor in blocks {
        let size = (descriptor & 0xffffffU).reinterpret_as_int()
        guard (descriptor & 0xfe000000U) == 0U &&
          at >= 96 &&
          at <= self.superblock.inode_table &&
          size <= self.superblock.inode_table - at else {
          raise Invalid(at, "file block extent")
        }
        result.push(at)
        at += size
      }
      // Keep only one file's prefix index to bound memory for huge inode sets.
      self.offsets.clear()
      self.offsets[file.reference] = result
      result
    }
  }
  let first = Int::min(blocks.length(), offset / bs)
  let last = Int::min(
    blocks.length(),
    (offset + length) / bs + (if (offset + length) % bs == 0 { 0 } else { 1 }),
  )
  for i in first..<last {
    let descriptor = blocks[i]
    let logical = i * bs
    let stored = offsets[i]
    let expected = Int::min(bs, size - logical)
    if logical < offset + length && logical + expected > offset {
      let data = if descriptor == 0U {
        Bytes::make(expected, 0)
      } else {
        self.data_block(stored, descriptor, expected)
      }
      guard data.length() == expected else {
        raise Invalid(stored, "file block length")
      }
      let from = Int::max(offset - logical, 0)
      let until = Int::min(offset + length - logical, expected)
      append_bytes(out, region(data, from, until - from))
    }
  }
  let logical = if fragment == 0xffffffffU { size } else { size / bs * bs }
  if fragment != 0xffffffffU && offset + length > logical {
    guard fragment.to_uint64() < self.superblock.fragments.to_uint64() else {
      raise Invalid(80, "fragment ID")
    }
    let n = fragment.reinterpret_as_int()
    let b = self.metadata(
      self.pointer(self.superblock.fragment_table + n / 512 * 8),
      n % 512 * 16,
      16,
    )
    let data = self.data_block(index(u64(b, 0), 0), u32(b, 8), bs)
    let from = Int::max(offset - logical, 0)
    let until = offset + length - logical
    append_bytes(out, region(data, fragment_offset + from, until - from))
  }
  guard out.length() == length else {
    raise Invalid(offset, "file range short output")
  }
  Bytes::from_array(out)
}
