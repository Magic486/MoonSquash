///|
test "hardlinks share metadata fragments xattrs and export identity" {
  let metadata : @moonsquash.BuildMetadata = {
    uid: 1234U,
    gid: 5678U,
    mtime: 42U,
    xattrs: [{ name: b"user.test", value: b"a\x00b", }],
  }
  let image = @moonsquash.open_image(
    @moonsquash.build_image(
      [
        { path: "/file", mode: 416, content: Regular(b"content"), },
        { path: "/alias", mode: 420, content: Hardlink("/file"), },
        { path: "/chain", mode: 420, content: Hardlink("/alias"), },
        { path: "/link", mode: 511, content: Symbolic(b"file"), },
      ],
      attributes=Map([("/file", metadata)]),
    ),
  )
  let node = image.lookup("/file")
  assert_eq(node.reference, image.lookup("/chain").reference)
  assert_eq(node.links, 3)
  assert_eq(node.uid, 1234U)
  assert_eq(node.gid, 5678U)
  assert_eq(node.mtime, 42U)
  assert_eq(image.xattrs(node), metadata.xattrs)
  assert_eq(image.export_inode(node.number).reference, node.reference)
  assert_eq(image.header().fragments, 1)
  let report = image.verify()
  assert_eq(report.inodes, 3)
  assert_eq(report.files, 1)
  assert_eq(report.xattrs, 1)
}

///|
test "xattrs cross metadata boundaries and special inodes retain attributes" {
  let attrs : Array[@moonsquash.Xattr] = [
    { name: b"user.large", value: Bytes::make(20000, 42), },
  ]
  let image = @moonsquash.open_image(
    @moonsquash.build_image(
      [
        { path: "/dev", mode: 384, content: CharDevice(259U), },
        { path: "/fifo", mode: 384, content: Fifo, },
        { path: "/socket", mode: 384, content: Socket, },
        { path: "/block", mode: 384, content: BlockDevice(2048U), },
      ],
      attributes=Map([
        ("/dev", { uid: 4000000000U, gid: 1U, mtime: 5U, xattrs: attrs, }),
      ]),
    ),
  )
  assert_eq(image.xattrs(image.lookup("/dev")), attrs)
  assert_eq(image.lookup("/dev").uid, 4000000000U)
  assert_eq(image.lookup("/socket").kind, 14)
  assert_eq(image.verify().inodes, 5)
}

///|
test "random source and ranges skip untouched data and handle sparse tails" {
  let data = Bytes::make(4096, 17) + Bytes::make(4096, 0) + b"tail"
  let bytes = @moonsquash.build_image(
    [{ path: "/file", mode: 420, content: Regular(data), }],
    block_size=4096,
  )
  let sizes : Array[Int] = []
  let image = @moonsquash.open_source(bytes.length(), (at, size) => {
    sizes.push(size)
    bytes[at:at + size].to_owned()
  })
  let node = image.lookup("/file")
  assert_eq(
    image.read_range(node, 4090, 12),
    Bytes::make(6, 17) + Bytes::make(6, 0),
  )
  assert_eq(image.read_range(node, 8190, 6), b"\x00\x00tail")
  assert_eq(image.read_range(node, data.length(), 0), b"")
  assert_true(sizes.iter().all(n => n <= 8192))
  ignore(image.verify())
}

///|
test "diff compares meaning across layout and detects link metadata content changes" {
  let entries : Array[@moonsquash.BuildEntry] = [
    { path: "/f", mode: 420, content: Regular(b"first"), },
    { path: "/g", mode: 420, content: Hardlink("/f"), },
  ]
  let before = @moonsquash.open_image(@moonsquash.build_image(entries))
  let layout = @moonsquash.open_image(
    @moonsquash.build_image(entries, fragments=false, exportable=false),
  )
  assert_eq(@moonsquash.diff_images(before, layout).length(), 0)
  let after = @moonsquash.open_image(
    @moonsquash.build_image([
      { path: "/f", mode: 384, content: Regular(b"second"), },
    ]),
  )
  let changes = @moonsquash.diff_images(before, after)
  assert_eq(changes.length(), 2)
  assert_eq(changes[0].path, "/f")
  assert_true(changes[0].changes.contains("content"))
  assert_true(changes[0].changes.contains("mode"))
  assert_true(changes[0].changes.contains("links"))
  assert_eq(changes[1].changes, ["removed"])
}

///|
test "reject unresolved cyclic and directory hardlinks" {
  let cases : Array[Array[@moonsquash.BuildEntry]] = [
    [{ path: "/a", mode: 420, content: @moonsquash.Hardlink("/b"), }],
    [
      { path: "/a", mode: 420, content: @moonsquash.Hardlink("/b"), },
      { path: "/b", mode: 420, content: @moonsquash.Hardlink("/a"), },
    ],
    [
      { path: "/a", mode: 420, content: @moonsquash.Hardlink("/d"), },
      { path: "/d", mode: 493, content: @moonsquash.Folder, },
    ],
  ]
  for entries in cases {
    let rejected = try {
      ignore(@moonsquash.build_image(entries))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "duplicate xattr and malformed random source rejected" {
  let rejected = try {
    ignore(
      @moonsquash.build_image(
        [{ path: "/f", mode: 420, content: Regular(b"x"), }],
        attributes=Map([
          (
            "/f",
            {
              uid: 0U,
              gid: 0U,
              mtime: 0U,
              xattrs: [
                { name: b"user.x", value: b"a", },
                { name: b"user.x", value: b"b", },
              ],
            },
          ),
        ]),
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let image = @moonsquash.build_image([])
  let source = @moonsquash.open_source(image.length(), (at, size) => {
    if at == 0 {
      image[:size].to_owned()
    } else {
      b""
    }
  })
  let rejected = try {
    ignore(source.root())
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
