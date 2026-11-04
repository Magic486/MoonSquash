///|
/// Check indexed metadata coverage and return the first compressed block.
fn Image::check_index(
  self : Image,
  table : Int,
  count : Int,
  width : Int,
  end : Int,
) -> Int raise SquashError {
  guard count > 0 && count <= 1000000 else {
    raise Limit("indexed table count")
  }
  let bytes = count * width
  let blocks = (bytes + 8191) / 8192
  guard table >= self.superblock.directory_table &&
    table <= end &&
    blocks * 8 == end - table else {
    raise Invalid(table, "index table extent")
  }
  let start = self.pointer(table)
  guard start >= self.superblock.directory_table && start < table else {
    raise Invalid(table, "index first block")
  }
  let mut next = start
  for i in 0..<blocks {
    guard self.pointer(table + i * 8) == next else {
      raise Invalid(table, "noncontiguous metadata index")
    }
    let (data, at) = self.metadata_block(next)
    guard data.length() == Int::min(8192, bytes - i * 8192) else {
      raise Invalid(next, "indexed metadata length")
    }
    next = at
  }
  guard next == table else {
    raise Invalid(next, "indexed metadata table boundary")
  }
  start
}

///|
fn Image::scan_metadata(
  self : Image,
  start : Int,
  end : Int,
) -> Map[Int, Bool] raise SquashError {
  let boundaries : Map[Int, Bool] = Map([])
  let mut at = start
  while at < end {
    boundaries[at] = true
    let (_, next) = self.metadata_block(at)
    guard next > at && next <= end else {
      raise Invalid(at, "metadata crosses table boundary")
    }
    at = next
  }
  guard at == end else { raise Invalid(at, "metadata table boundary") }
  boundaries
}

///|
fn Image::validate_layout(
  self : Image,
  tree : Array[TreeEntry],
) -> Unit raise SquashError {
  let h = self.superblock
  guard h.inodes <= 100000 && h.fragments <= 1000000 else {
    raise Limit("verification table count")
  }
  guard (h.flags & 0xf000) == 0 else {
    raise Invalid(24, "reserved superblock flags")
  }
  guard ((h.flags & 0x80) != 0) == (h.export_table != 0xffffffffffffffffUL) else {
    raise Invalid(88, "export flag/table mismatch")
  }
  guard (h.flags & 0x10) == 0 || h.fragments == 0 else {
    raise Invalid(16, "no-fragments flag mismatch")
  }
  let mut end = h.bytes_used
  if h.xattr_table != 0xffffffffffffffffUL {
    guard (h.flags & 0x200) == 0 else {
      raise Invalid(56, "no-xattrs flag mismatch")
    }
    let (start, count, index_table) = self.xattr_header()
    // The xattr header separates metadata from its index.
    let blocks = (count * 16 + 8191) / 8192
    guard index_table + blocks * 8 == end else {
      raise Invalid(index_table, "xattr index extent")
    }
    let mut next = self.pointer(index_table)
    let ids_start = next
    for i in 0..<blocks {
      guard self.pointer(index_table + i * 8) == next else {
        raise Invalid(next, "xattr ID index")
      }
      let (data, after) = self.metadata_block(next)
      guard data.length() == Int::min(8192, count * 16 - i * 8192) else {
        raise Invalid(next, "xattr ID metadata length")
      }
      next = after
    }
    guard next == index_table - 16 else {
      raise Invalid(next, "xattr ID table boundary")
    }
    ignore(self.scan_metadata(start, ids_start))
    end = start
  }
  end = self.check_index(h.id_table, h.ids, 4, end)
  if h.export_table != 0xffffffffffffffffUL {
    end = self.check_index(index(h.export_table, 88), h.inodes, 8, end)
  }
  if h.fragments > 0 {
    end = self.check_index(h.fragment_table, h.fragments, 16, end)
  }
  let directory_end = end
  let dir_blocks = self.scan_metadata(h.directory_table, directory_end)
  let inode_blocks = self.scan_metadata(h.inode_table, h.directory_table)
  for e in tree {
    let relative = index(e.inode.reference >> 16, 32)
    guard inode_blocks.contains(h.inode_table + relative) else {
      raise Invalid(relative, "inode points inside a metadata block")
    }
    if e.inode.content is Directory(block, _, size) {
      guard size == 0 || dir_blocks.contains(block) else {
        raise Invalid(block, "directory points inside a metadata block")
      }
      let cursor : Cursor = {
        image: self,
        block,
        offset: match e.inode.content {
          Directory(_, off, _) => off
          _ => 0
        },
      }
      ignore(cursor.take(size))
      guard cursor.block <= directory_end &&
        (cursor.block < directory_end || cursor.offset == 0) else {
        raise Invalid(block, "directory extent crosses table")
      }
    }
  }
  // Walk every packed inode record, catching unreachable records and references
  // into the middle of records, including extended directory index payloads.
  let cursor : Cursor = { image: self, block: h.inode_table, offset: 0, }
  let references : Map[UInt64, Bool] = Map([])
  for _ in 0..<h.inodes {
    let reference = ((cursor.block - h.inode_table).to_uint64() << 16) |
      cursor.offset.to_uint64()
    references[reference] = true
    let base = cursor.take(16)
    let kind = u16(base, 0)
    match kind {
      1 => ignore(cursor.take(16))
      8 => {
        let b = cursor.take(24)
        let count = u16(b, 16)
        for _ in 0..<count {
          let idx = cursor.take(12)
          let name_size = index(u32(idx, 8).to_uint64(), cursor.block)
          guard name_size < 256 else {
            raise Invalid(cursor.block, "directory index name length")
          }
          ignore(cursor.take(name_size + 1))
        }
      }
      2 | 9 => {
        let b = cursor.take(if kind == 2 { 16 } else { 40 })
        let size = if kind == 2 {
          index(u32(b, 12).to_uint64(), cursor.block)
        } else {
          index(u64(b, 8), cursor.block)
        }
        let fragment = u32(b, if kind == 2 { 4 } else { 28 })
        if kind == 9 {
          guard u64(b, 16) <= size.to_uint64() else {
            raise Invalid(cursor.block, "sparse byte count exceeds file size")
          }
        }
        let blocks = size / h.block_size +
          (if fragment == 0xffffffffU && size % h.block_size != 0 {
            1
          } else {
            0
          })
        ignore(cursor.take(blocks * 4))
      }
      3 | 10 => {
        let b = cursor.take(8)
        let size = index(u32(b, 4).to_uint64(), cursor.block)
        guard size > 0 && size <= 65536 else { raise Limit("symlink size") }
        ignore(cursor.take(size + (if kind == 10 { 4 } else { 0 })))
      }
      4 | 5 => ignore(cursor.take(8))
      6 | 7 => ignore(cursor.take(4))
      11 | 12 => ignore(cursor.take(12))
      13 | 14 => ignore(cursor.take(8))
      _ => raise Invalid(cursor.block, "unknown inode record")
    }
    guard cursor.block <= h.directory_table else {
      raise Invalid(cursor.block, "inode record crosses table")
    }
  }
  guard cursor.block == h.directory_table && cursor.offset == 0 else {
    raise Invalid(
      cursor.block,
      "inode table contains excess records or trailing bytes",
    )
  }
  for e in tree {
    guard references.contains(e.inode.reference) else {
      raise Invalid(e.inode.number, "reference is not inode start")
    }
  }
}
