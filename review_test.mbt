///|
test "compressed metadata references survive child-first cross-block layout" {
  // An in-process codec stub tests the callback/reference contract on both
  // backends. Real compressor compatibility is covered by official Linux tools.
  let packets : Array[Bytes] = []
  let entries : Array[@moonsquash.BuildEntry] = []
  let attributes : Map[String, @moonsquash.BuildMetadata] = Map([])
  for i in 0..<1100 {
    attributes["/dir-\{i%8}/item-\{i}"] = {
      uid: (i * 2 + 1).reinterpret_as_uint(),
      gid: (i * 2 + 2).reinterpret_as_uint(),
      mtime: 0U,
      xattrs: [{ name: b"user.index", value: @utf8.encode("value-\{i}"), }],
    }
    entries.push({
      path: "/dir-\{i%8}/item-\{i}",
      mode: 420,
      content: Regular(b"value"),
    })
  }
  entries.push({
    path: "/deep/alias",
    mode: 420,
    content: Hardlink("/dir-0/item-0"),
  })
  let image = @moonsquash.open_image(
    @moonsquash.build_image(
      entries,
      attributes~,
      encode=Some((_id, data) => {
        guard packets.length() < 256 else {
          raise @moonsquash.Limit("test codec slots")
        }
        packets.push(data)
        Bytes::from_array([(packets.length() - 1).to_byte()])
      }),
    ),
    decode=(_id, stored, limit) => {
      guard stored.length() == 1 && stored[0].to_int() < packets.length() else {
        raise @moonsquash.Invalid(0, "test codec reference")
      }
      let result = packets[stored[0].to_int()]
      guard result.length() <= limit else {
        raise @moonsquash.Limit("test codec output")
      }
      result
    },
  )
  assert_eq(image.header().flags & 0x901, 0)
  assert_eq(image.verify().files, 1100)
  assert_eq(image.verify().xattrs, 1100)
  assert_eq(image.header().ids, 2201)
  assert_eq(
    image.xattrs(image.lookup("/dir-3/item-1099"))[0].value,
    b"value-1099",
  )
  assert_eq(image.read_file(image.lookup("/deep/alias")), b"value")
  assert_eq(
    image.lookup("/deep/alias").reference,
    image.lookup("/dir-0/item-0").reference,
  )
}

///|
test "verification enforces aggregate decoded-byte budget" {
  let image = @moonsquash.open_image(
    @moonsquash.build_image([
      { path: "/a", mode: 420, content: Regular(Bytes::make(4096, 0)), },
      { path: "/b", mode: 420, content: Regular(Bytes::make(4096, 0)), },
    ]),
  )
  let rejected = try {
    ignore(image.verify(max_bytes=4096UL))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(image.verify(max_bytes=8192UL).bytes_checked, 8192UL)
}

///|
test "streaming builder bounds reads and produces the same image as memory build" {
  let data = Bytes::make(20000, 42) + b"tail"
  let bytes : Array[Byte] = []
  let requests : Array[Int] = []
  let header = @moonsquash.build_to(
    [
      { path: "/f", mode: 420, content: External(data.length()), },
      { path: "/alias", mode: 420, content: Hardlink("/f"), },
    ],
    (at, chunk) => {
      if at == bytes.length() {
        for b in chunk {
          bytes.push(b)
        }
      } else {
        for i in 0..<chunk.length() {
          bytes[at + i] = chunk[i]
        }
      }
    },
    (path, at, size) => {
      guard path == "/f" else {
        raise @moonsquash.Invalid(at, "unexpected source")
      }
      requests.push(size)
      data[at:at + size].to_owned()
    },
    block_size=4096,
  )
  assert_true(requests.iter().all(n => n <= 4096))
  let image = Bytes::from_array(bytes)
  assert_eq(header.bytes_used, image.length())
  assert_eq(
    image,
    @moonsquash.build_image(
      [
        { path: "/f", mode: 420, content: Regular(data), },
        { path: "/alias", mode: 420, content: Hardlink("/f"), },
      ],
      block_size=4096,
    ),
  )
  assert_eq(@moonsquash.open_image(image).verify().files, 1)
  let rejected = try {
    ignore(
      @moonsquash.build_to(
        [{ path: "/f", mode: 420, content: External(3), }],
        (_, _data) => (),
        (_, _at, _size) => b"x",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
