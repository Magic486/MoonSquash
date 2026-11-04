///|
pub(all) suberror SquashError {
  Invalid(Int, String)
  Unsupported(String)
  Limit(String)
} derive(Debug)

///|
pub(all) struct Superblock {
  inodes : Int
  created : UInt
  block_size : Int
  fragments : Int
  compression : Int
  flags : Int
  ids : Int
  root : UInt64
  bytes_used : Int
  inode_table : Int
  directory_table : Int
  fragment_table : Int
  id_table : Int
  xattr_table : UInt64
  export_table : UInt64
} derive(Debug)

///|
pub(all) enum Content {
  Directory(Int, Int, Int)
  File(Int, Int, UInt, Int, Array[UInt])
  Symlink(Bytes)
  Device(UInt)
  Special
} derive(Debug)

///|
pub(all) struct Inode {
  reference : UInt64
  number : Int
  kind : Int
  mode : Int
  uid : UInt
  gid : UInt
  mtime : UInt
  links : Int
  content : Content
} derive(Debug)

///|
pub(all) struct DirEntry {
  name : Bytes
  reference : UInt64
  number : Int
  kind : Int
} derive(Debug)

///|
pub struct Image {
  bytes : Bytes
  superblock : Superblock
  decode : (Int, Bytes, Int) -> Bytes raise SquashError
}

///|
pub fn Image::header(self : Image) -> Superblock {
  self.superblock
}

///|
pub fn no_decompressor(
  id : Int,
  _bytes : Bytes,
  _limit : Int,
) -> Bytes raise SquashError {
  raise Unsupported("compression algorithm \{id} needs a decoder")
}
