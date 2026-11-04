///|
test "empty image has a root and deterministic header" {
  let bytes = @moonsquash.build_image([])
  let image = @moonsquash.open_image(bytes)
  assert_eq(image.header().inodes, 1)
  assert_eq(image.header().bytes_used, bytes.length())
  assert_eq(image.tree().length(), 1)
  assert_eq(image.entries(image.root()).length(), 0)
  assert_eq(bytes, @moonsquash.build_image([]))
}

///|
test "nested files modes symlink and automatic parents" {
  let image = @moonsquash.open_image(
    @moonsquash.build_image([
      { path: "/a/file", mode: 416, content: Regular(b"hello"), },
      { path: "/link", mode: 511, content: Symbolic(b"a/file"), },
      { path: "/empty", mode: 493, content: Folder, },
    ]),
  )
  assert_eq(image.tree().length(), 5)
  let node = image.lookup("/a/file")
  assert_eq(node.mode, 416)
  assert_eq(image.read_file(node), b"hello")
  assert_true(image.lookup("/link").content is Symlink(b"a/file"))
}

///|
test "sparse blocks and partial tail" {
  let payload = Bytes::make(8192, 0) + b"tail"
  let image = @moonsquash.open_image(
    @moonsquash.build_image(
      [{ path: "/sparse", mode: 420, content: Regular(payload), }],
      block_size=4096,
    ),
  )
  assert_eq(image.read_file(image.lookup("/sparse")), payload)
  assert_true(image.header().bytes_used < 4096)
}

///|
test "inode and directory metadata cross block boundaries" {
  let entries : Array[@moonsquash.BuildEntry] = []
  for i in 0..<500 {
    entries.push({
      path: "/files/item-\{i}",
      mode: 420,
      content: Regular(b"data"),
    })
  }
  let image = @moonsquash.open_image(@moonsquash.build_image(entries))
  assert_eq(image.tree().length(), 502)
  for i in [0, 127, 128, 255, 256, 499] {
    assert_eq(image.read_file(image.lookup("/files/item-\{i}")), b"data")
  }
}

///|
test "construction is independent of input ordering" {
  let a : @moonsquash.BuildEntry = {
    path: "/z",
    mode: 420,
    content: Regular(b"z"),
  }
  let b : @moonsquash.BuildEntry = {
    path: "/a",
    mode: 420,
    content: Regular(b"a"),
  }
  assert_eq(@moonsquash.build_image([a, b]), @moonsquash.build_image([b, a]))
}

///|
test "directory names use byte lexical order rather than shortlex" {
  let image = @moonsquash.open_image(
    @moonsquash.build_image([
      { path: "/z", mode: 420, content: Regular(b""), },
      { path: "/aaa", mode: 420, content: Regular(b""), },
      { path: "/aa", mode: 420, content: Regular(b""), },
    ]),
  )
  assert_eq(image.entries(image.root()).map(e => e.name), [b"aa", b"aaa", b"z"])
}

///|
test "reject traversal and duplicate paths" {
  for path in ["relative", "/a/../b", "/a//b", "/.", "/"] {
    let rejected = try {
      ignore(
        @moonsquash.build_image([{ path, mode: 420, content: Regular(b""), }]),
      )
      false
    } catch {
      @moonsquash.Invalid(_, _) => true
      _ => false
    }
    assert_true(rejected)
  }
  let e : @moonsquash.BuildEntry = {
    path: "/a",
    mode: 420,
    content: Regular(b""),
  }
  let rejected = try {
    ignore(@moonsquash.build_image([e, e]))
    false
  } catch {
    @moonsquash.Invalid(_, _) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "reject a file as a parent regardless of input order" {
  let a : @moonsquash.BuildEntry = {
    path: "/a",
    mode: 420,
    content: Regular(b""),
  }
  let b : @moonsquash.BuildEntry = {
    path: "/a/b",
    mode: 420,
    content: Regular(b""),
  }
  for entries in [[a, b], [b, a]] {
    let rejected = try {
      ignore(@moonsquash.build_image(entries))
      false
    } catch {
      @moonsquash.Invalid(_, _) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "truncation and corrupted superblocks are rejected" {
  let valid = @moonsquash.build_image([])
  for size in [0, 4, 95, valid.length() - 1] {
    let rejected = try {
      ignore(@moonsquash.open_image(valid[:size].to_owned()))
      false
    } catch {
      @moonsquash.Invalid(_, _) => true
      _ => false
    }
    assert_true(rejected)
  }
  for offset in [0, 12, 22, 40, 64] {
    let bad = valid.to_array()
    bad[offset] = 0xff
    let rejected = try {
      ignore(@moonsquash.open_image(Bytes::from_array(bad)))
      false
    } catch {
      @moonsquash.Invalid(_, _) => true
      @moonsquash.Limit(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "read and traversal budgets are enforced" {
  let image = @moonsquash.open_image(
    @moonsquash.build_image([
      { path: "/a", mode: 420, content: Regular(b"hello"), },
    ]),
  )
  let rejected = try {
    ignore(image.read_file(image.lookup("/a"), max_bytes=4))
    false
  } catch {
    @moonsquash.Limit(_) => true
    _ => false
  }
  assert_true(rejected)
  let rejected = try {
    ignore(image.tree(max_entries=1))
    false
  } catch {
    @moonsquash.Limit(_) => true
    _ => false
  }
  assert_true(rejected)
}
