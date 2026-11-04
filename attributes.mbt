///|
/// Raw attribute names and values; values are never interpreted as text.
pub(all) struct Xattr {
  name : Bytes
  value : Bytes
} derive(Debug, Eq)

///|
priv struct Cursor {
  image : Image
  mut block : Int
  mut offset : Int
}

///|
fn Cursor::take(self : Cursor, size : Int) -> Bytes raise SquashError {
  guard size >= 0 && size <= 16777216 else { raise Limit("attribute size") }
  let out : Array[Byte] = []
  while out.length() < size {
    let (b, next) = self.image.metadata_block(self.block)
    guard self.offset >= 0 && self.offset <= b.length() else {
      raise Invalid(self.block, "cursor offset")
    }
    let n = Int::min(size - out.length(), b.length() - self.offset)
    append_bytes(out, region(b, self.offset, n))
    self.offset += n
    if self.offset == b.length() {
      self.block = next
      self.offset = 0
    }
  }
  Bytes::from_array(out)
}

///|
fn Image::xattr_header(self : Image) -> (Int, Int, Int) raise SquashError {
  let table = index(self.superblock.xattr_table, 56)
  let b = self.range(table, 16)
  let start = index(u64(b, 0), table)
  let count = index(u32(b, 8).to_uint64(), table)
  guard count > 0 &&
    count <= 1000000 &&
    start >= self.superblock.id_table &&
    start < table &&
    u32(b, 12) == 0U else {
    raise Invalid(table, "xattr table header")
  }
  ignore(self.range(table + 16, (count + 511) / 512 * 8))
  (start, count, table + 16)
}

///|
fn Image::xattr_id(self : Image, id : UInt) -> Array[Xattr] raise SquashError {
  if id == 0xffffffffU {
    return []
  }
  let (start, count, table) = self.xattr_header()
  guard id.to_uint64() < count.to_uint64() else {
    raise Invalid(table, "xattr ID out of range")
  }
  let n = id.reinterpret_as_int()
  let record = self.metadata(
    self.pointer(table + n / 512 * 8),
    n % 512 * 16,
    16,
  )
  let reference = u64(record, 0)
  let attrs = index(u32(record, 8).to_uint64(), table)
  let declared = index(u32(record, 12).to_uint64(), table)
  guard attrs <= 65536 && declared <= 16777216 else {
    raise Limit("xattr list budget")
  }
  let cursor : Cursor = {
    image: self,
    block: start + index(reference >> 16, table),
    offset: (reference & 0xffffUL).to_int(),
  }
  let result : Array[Xattr] = []
  let seen : Map[Bytes, Bool] = Map([])
  let mut total = 0
  for _ in 0..<attrs {
    let head = cursor.take(4)
    let kind = u16(head, 0)
    guard (kind & 0xfe00) == 0 else { raise Invalid(table, "xattr flags") }
    let prefix = match kind & 255 {
      0 => b"user."
      1 => b"trusted."
      2 => b"security."
      _ => raise Unsupported("xattr namespace")
    }
    let size = u16(head, 2)
    guard size > 0 && size + prefix.length() <= 255 else {
      raise Invalid(table, "xattr name length")
    }
    let name = prefix + cursor.take(size)
    guard !name.iter().any(b => b == 0) && !seen.contains(name) else {
      raise Invalid(table, "duplicate or invalid xattr name")
    }
    seen[name] = true
    let length = index(u32(cursor.take(4), 0).to_uint64(), table)
    let value = if (kind & 256) != 0 {
      guard length == 8 else {
        raise Invalid(table, "out-of-line xattr reference size")
      }
      let value_ref = u64(cursor.take(8), 0)
      let other : Cursor = {
        image: self,
        block: start + index(value_ref >> 16, table),
        offset: (value_ref & 0xffffUL).to_int(),
      }
      let len = index(u32(other.take(4), 0).to_uint64(), table)
      other.take(len)
    } else {
      cursor.take(length)
    }
    guard value.length() <= 16777216 - total - name.length() - 1 else {
      raise Limit("xattr total budget")
    }
    total += name.length() + 1 + value.length()
    result.push({ name, value, })
  }
  guard total == declared else {
    raise Invalid(table, "xattr list size mismatch")
  }
  result
}

///|
pub fn Image::xattrs(
  self : Image,
  inode : Inode,
) -> Array[Xattr] raise SquashError {
  self.xattr_id(inode.xattr)
}

///|
/// Resolve the optional NFS export index by inode number.
pub fn Image::export_inode(
  self : Image,
  number : Int,
) -> Inode raise SquashError {
  guard number >= 1 && number <= self.superblock.inodes else {
    raise Invalid(number, "export inode number")
  }
  if self.superblock.export_table == 0xffffffffffffffffUL {
    raise Unsupported("image has no export table")
  }
  let table = index(self.superblock.export_table, 88)
  let n = number - 1
  let record = self.metadata(
    self.pointer(table + n / 1024 * 8),
    n % 1024 * 8,
    8,
  )
  let inode = self.inode(u64(record, 0))
  guard inode.number == number else {
    raise Invalid(table, "export index identity mismatch")
  }
  inode
}
