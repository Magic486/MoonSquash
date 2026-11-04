///|
pub(all) struct TreeEntry {
  path : String
  inode : Inode
} derive(Debug)

///|
fn walk_tree(
  image : Image,
  node : Inode,
  path : String,
  depth : Int,
  ancestors : Array[Int],
  out : Array[TreeEntry],
  max_entries : Int,
) -> Unit raise SquashError {
  guard depth <= 128 && out.length() < max_entries else {
    raise Limit("tree traversal budget")
  }
  out.push({ path, inode: node, })
  if node.content is Directory(_, _, _) {
    guard !ancestors.contains(node.number) else {
      raise Invalid(node.number, "directory cycle")
    }
    ancestors.push(node.number)
    for entry in image.entries(node) {
      let child = image.inode(entry.reference)
      let basic_kind = if child.kind > 7 { child.kind - 7 } else { child.kind }
      guard child.number == entry.number && basic_kind == entry.kind else {
        raise Invalid(child.number, "directory/inode identity mismatch")
      }
      let name = @utf8.decode(entry.name) catch {
        _ =>
          raise Unsupported(
            "tree string paths require UTF-8; use entries for raw names",
          )
      }
      let child_path = if path == "/" { "/\{name}" } else { "\{path}/\{name}" }
      walk_tree(
        image,
        child,
        child_path,
        depth + 1,
        ancestors,
        out,
        max_entries,
      )
    }
    ignore(ancestors.pop())
  }
}

///|
pub fn Image::tree(
  self : Image,
  max_entries? : Int = 100000,
) -> Array[TreeEntry] raise SquashError {
  let out : Array[TreeEntry] = []
  let root = self.root()
  guard root.content is Directory(_, _, _) else {
    raise Invalid(root.number, "root is not a directory")
  }
  walk_tree(self, root, "/", 0, [], out, max_entries)
  out
}
