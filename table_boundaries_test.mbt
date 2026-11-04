///|
test "multi-block ID export and xattr indexes resolve independently" {
  let entries : Array[@moonsquash.BuildEntry] = []
  let attributes : Map[String, @moonsquash.BuildMetadata] = Map([])
  for i in 0..<1100 {
    let path = "/file-\{i}"
    entries.push({ path, mode: 420, content: Regular(b"fragment"), })
    attributes[path] = {
      uid: (i * 2 + 1).reinterpret_as_uint(),
      gid: (i * 2 + 2).reinterpret_as_uint(),
      mtime: 0U,
      xattrs: [{ name: b"user.index", value: @utf8.encode("\{i}"), }],
    }
  }
  let image = @moonsquash.open_image(
    @moonsquash.build_image(entries, attributes~, block_size=4096),
  )
  assert_eq(image.header().ids, 2201)
  assert_eq(image.header().inodes, 1101)
  for i in [0, 511, 512, 1023, 1024, 1099] {
    let node = image.lookup("/file-\{i}")
    assert_eq(image.export_inode(node.number).reference, node.reference)
    assert_eq(node.uid, (i * 2 + 1).reinterpret_as_uint())
    assert_eq(image.xattrs(node)[0].value, @utf8.encode("\{i}"))
    assert_eq(image.read_range(node, 1, 7), b"ragment")
  }
  assert_eq(image.verify().xattrs, 1100)
}

///|
test "root metadata and optional table profiles are preserved" {
  let image = @moonsquash.open_image(
    @moonsquash.build_image(
      [
        { path: "/", mode: 488, content: Folder, },
        { path: "/f", mode: 0, content: Regular(b"abc"), },
      ],
      attributes=Map([
        (
          "/",
          {
            uid: 42U,
            gid: 43U,
            mtime: 100U,
            xattrs: [{ name: b"user.root", value: b"root", }],
          },
        ),
      ]),
      fragments=false,
      exportable=false,
    ),
  )
  assert_eq(image.root().mode, 488)
  assert_eq(image.root().uid, 42U)
  assert_eq(image.root().mtime, 100U)
  assert_eq(image.header().fragments, 0)
  assert_eq(image.verify().export_checked, false)
}
