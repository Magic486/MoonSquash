///|
pub(all) struct VerifyReport {
  entries : Int
  inodes : Int
  files : Int
  bytes_checked : UInt64
  xattrs : Int
  fragments : Int
  export_checked : Bool
} derive(Debug)

///|
/// Validate the reachable filesystem, IDs, fragments, export index and xattrs.
/// Fails on the first inconsistency; decompression errors propagate to the caller.
pub fn Image::verify(self : Image) -> VerifyReport raise SquashError {
  let tree = self.tree()
  self.validate_layout(tree)
  let unique : Map[Int, Inode] = Map([])
  let counts : Map[Int, Int] = Map([])
  let mut files = 0
  let mut bytes = 0UL
  let mut xattrs = 0
  let directories : Map[String, Int] = Map([])
  for e in tree {
    if e.inode.content is Directory(_, _, _) {
      directories[e.path] = e.inode.number
    }
  }
  for entry in tree {
    let node = entry.inode
    guard node.mode <= 4095 && node.links > 0 else {
      raise Invalid(node.number, "mode or link count")
    }
    counts[node.number] = counts.get(node.number).unwrap_or(0) + 1
    if unique.get(node.number) is Some(previous) {
      guard previous.reference == node.reference &&
        !(node.content is Directory(_, _, _)) else {
        raise Invalid(node.number, "inode alias or directory hard link")
      }
      continue
    }
    unique[node.number] = node
    xattrs += self.xattrs(node).length()
    match node.content {
      Directory(_, _, _) => {
        if entry.path == "/" {
          guard node.parent == node.number ||
            node.parent == self.superblock.inodes + 1 else {
            raise Invalid(node.number, "root parent")
          }
        } else {
          let parts = entry.path.split("/").map(p => p.to_owned()).to_array()
          ignore(parts.pop())
          let parent = if parts.length() == 1 { "/" } else { parts.join("/") }
          guard directories.get(parent) is Some(number) && number == node.parent else {
            raise Invalid(node.number, "directory parent mismatch")
          }
        }
        let children = self.entries(node)
        let mut previous : Bytes? = None
        let mut directories = 0
        for child in children {
          if previous is Some(name) {
            guard name.lexical_compare(child.name) < 0 else {
              raise Invalid(node.number, "directory not byte sorted")
            }
          }
          previous = Some(child.name)
          if child.kind == 1 {
            directories += 1
          }
        }
        guard node.links == directories + 2 else {
          raise Invalid(node.number, "directory link count")
        }
      }
      File(_, size, frag, off, _) => {
        if frag != 0xffffffffU {
          guard size % self.superblock.block_size != 0 &&
            off < self.superblock.block_size else {
            raise Invalid(node.number, "invalid file fragment")
          }
        }
        let mut at = 0
        while at < size {
          let n = Int::min(self.superblock.block_size, size - at)
          ignore(self.read_range(node, at, n))
          at += n
        }
        bytes += size.to_uint64()
        files += 1
      }
      Symlink(target) => {
        guard !target.iter().any(c => c == 0) else {
          raise Invalid(node.number, "NUL symlink")
        }
      }
      _ => ()
    }
  }
  guard unique.length() == self.superblock.inodes else {
    raise Invalid(4, "unreachable or missing inodes")
  }
  for number, node in unique {
    if !(node.content is Directory(_, _, _)) && node.kind != 2 {
      guard counts[number] == node.links else {
        raise Invalid(number, "hard-link count mismatch")
      }
    }
  }
  for i in 0..<self.superblock.ids {
    ignore(self.identity(i))
  }
  for i in 0..<self.superblock.fragments {
    let table = self.superblock.fragment_table
    let b = self.metadata(self.pointer(table + i / 512 * 8), i % 512 * 16, 16)
    guard u32(b, 12) == 0U else {
      raise Invalid(table, "fragment reserved field")
    }
    ignore(
      self.data_block(
        index(u64(b, 0), table),
        u32(b, 8),
        self.superblock.block_size,
      ),
    )
  }
  if self.superblock.xattr_table != 0xffffffffffffffffUL {
    let (_, count, _) = self.xattr_header()
    for i in 0..<count {
      ignore(self.xattr_id(i.reinterpret_as_uint()))
    }
  }
  let export_checked = self.superblock.export_table != 0xffffffffffffffffUL
  if export_checked {
    for i in 1..<=self.superblock.inodes {
      let node = self.export_inode(i)
      guard unique.get(i) is Some(expected) &&
        expected.reference == node.reference else {
        raise Invalid(i, "export index is not reachable")
      }
    }
  }
  {
    entries: tree.length(),
    inodes: unique.length(),
    files,
    bytes_checked: bytes,
    xattrs,
    fragments: self.superblock.fragments,
    export_checked,
  }
}
