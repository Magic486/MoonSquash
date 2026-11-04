///|
pub(all) struct Difference {
  path : String
  changes : Array[String]
} derive(Debug)

///|
fn link_groups(tree : Array[TreeEntry]) -> Map[Int, Array[String]] {
  let groups : Map[Int, Array[String]] = Map([])
  for e in tree {
    if groups.get(e.inode.number) is Some(paths) {
      paths.push(e.path)
    } else {
      groups[e.inode.number] = [e.path]
    }
  }
  for paths in groups.values() {
    paths.sort()
  }
  groups
}

///|
/// Compare filesystem meaning independently of compression and inode numbering.
pub fn diff_images(
  before : Image,
  after : Image,
) -> Array[Difference] raise SquashError {
  let left = before.tree()
  let right = after.tree()
  let lm : Map[String, Inode] = Map([])
  let rm : Map[String, Inode] = Map([])
  let paths : Map[String, Bool] = Map([])
  for e in left {
    lm[e.path] = e.inode
    paths[e.path] = true
  }
  for e in right {
    rm[e.path] = e.inode
    paths[e.path] = true
  }
  let lg = link_groups(left)
  let rg = link_groups(right)
  let names = paths.keys().to_array()
  names.sort_by((a, b) => @utf8.encode(a).lexical_compare(@utf8.encode(b)))
  let result : Array[Difference] = []
  for path in names {
    let changes : Array[String] = []
    match (lm.get(path), rm.get(path)) {
      (None, Some(_)) => changes.push("added")
      (Some(_), None) => changes.push("removed")
      (Some(a), Some(b)) => {
        let ak = if a.kind > 7 { a.kind - 7 } else { a.kind }
        let bk = if b.kind > 7 { b.kind - 7 } else { b.kind }
        if ak != bk {
          changes.push("type")
        }
        if a.mode != b.mode {
          changes.push("mode")
        }
        if a.uid != b.uid || a.gid != b.gid {
          changes.push("owner")
        }
        if a.mtime != b.mtime {
          changes.push("mtime")
        }
        let ax = before.xattrs(a)
        let bx = after.xattrs(b)
        ax.sort_by((x, y) => x.name.lexical_compare(y.name))
        bx.sort_by((x, y) => x.name.lexical_compare(y.name))
        if ax != bx {
          changes.push("xattrs")
        }
        if lg[a.number] != rg[b.number] {
          changes.push("links")
        }
        match (a.content, b.content) {
          (File(_, sa, _, _, _), File(_, sb, _, _, _)) => {
            let mut equal = sa == sb
            let mut at = 0
            while equal && at < sa {
              let n = Int::min(65536, sa - at)
              equal = before.read_range(a, at, n) == after.read_range(b, at, n)
              at += n
            }
            if !equal {
              changes.push("content")
            }
          }
          (Symlink(x), Symlink(y)) => if x != y { changes.push("target") }
          (Device(x), Device(y)) => if x != y { changes.push("device") }
          _ => ()
        }
      }
      _ => ()
    }
    if changes.length() > 0 {
      result.push({ path, changes, })
    }
  }
  result
}
