///|
/// Return validated codec options, if stored in the image. Values not needed
/// by the caller's decoder remain in their original wire representation.
pub fn Image::compression_options(self : Image) -> Bytes? raise SquashError {
  if (self.superblock.flags & 0x400) == 0 {
    guard self.superblock.compression != 5 else {
      raise Invalid(24, "LZ4 requires compressor options")
    }
    return None
  }
  let (options, next) = self.metadata_block(96)
  guard next <= self.superblock.inode_table else {
    raise Invalid(96, "compressor options cross data area")
  }
  let expected = match self.superblock.compression {
    1 | 3 | 4 | 5 => 8
    6 => 4
    _ => raise Unsupported("legacy LZMA compressor options")
  }
  guard options.length() == expected else {
    raise Invalid(96, "compressor option length")
  }
  if self.superblock.compression == 5 {
    guard u32(options, 0) == 1U && (u32(options, 4) & 0xfffffffeU) == 0U else {
      raise Invalid(96, "unsupported LZ4 version/flags")
    }
  }
  Some(options)
}

///|
fn Image::validate_data_extents(
  self : Image,
  tree : Array[TreeEntry],
) -> Unit raise SquashError {
  ignore(self.compression_options())
  let lower = if (self.superblock.flags & 0x400) != 0 {
    self.metadata_block(96).1
  } else {
    96
  }
  let spans : Map[Int, UInt] = Map([])
  let add = fn(at : Int, descriptor : UInt) -> Unit raise SquashError {
    let size = (descriptor & 0xffffffU).reinterpret_as_int()
    guard (descriptor & 0xfe000000U) == 0U &&
      size > 0 &&
      at >= lower &&
      at <= self.superblock.inode_table &&
      size <= self.superblock.inode_table - at else {
      raise Invalid(at, "data extent outside data area")
    }
    if spans.get(at) is Some(previous) {
      guard previous == descriptor else {
        raise Invalid(at, "inconsistent shared data descriptor")
      }
    } else {
      spans[at] = descriptor
    }
  }
  let seen : Map[Int, Bool] = Map([])
  for entry in tree {
    if seen.contains(entry.inode.number) {
      continue
    }
    seen[entry.inode.number] = true
    if entry.inode.content is File(start, _, _, _, blocks) {
      let mut at = start
      for descriptor in blocks {
        if descriptor != 0U {
          add(at, descriptor)
          at += (descriptor & 0xffffffU).reinterpret_as_int()
        }
      }
    }
  }
  for i in 0..<self.superblock.fragments {
    let table = self.superblock.fragment_table
    let record = self.metadata(
      self.pointer(table + i / 512 * 8),
      i % 512 * 16,
      16,
    )
    add(index(u64(record, 0), table), u32(record, 8))
  }
  let starts = spans.keys().to_array()
  starts.sort()
  let mut end = lower
  for at in starts {
    guard at >= end else {
      raise Invalid(at, "partially overlapping data extents")
    }
    end = at + (spans[at] & 0xffffffU).reinterpret_as_int()
  }
}
