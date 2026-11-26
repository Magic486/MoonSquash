///|
test "random access header obeys exact read contract" {
  let data = @moonsquash.build_image([])
  for extra in [-1, 1] {
    let rejected = try {
      ignore(
        @moonsquash.open_source(data.length(), (_, size) => {
          data[0:size + extra].to_owned()
        }),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  let called = Ref(false)
  let rejected = try {
    ignore(
      @moonsquash.open_source(95, (_, _) => {
        called.val = true
        data[0:96].to_owned()
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_false(called.val)
}

///|
test "lookup rejects directory entry type disagreement" {
  let data = @moonsquash.build_image(
    [{ path: "/f", mode: 420, content: Regular(b"abc"), }],
    metadata_compression=false,
  )
  let table = @moonsquash.read_superblock(data).directory_table
  let bytes = data.to_array()
  // Raw metadata header, directory group header, then entry kind.
  bytes[table + 2 + 12 + 4] = 6
  let image = @moonsquash.open_image(Bytes::from_array(bytes))
  let rejected = try {
    ignore(image.lookup("/f"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "sparse accounting accepts zero full blocks and short tails" {
  for size in [0, 4096, 4097, 8191] {
    let image = @moonsquash.open_image(
      @moonsquash.build_image(
        [
          {
            path: "/sparse",
            mode: 420,
            content: Regular(Bytes::make(size, 0)),
          },
        ],
        block_size=4096,
        fragments=false,
      ),
    )
    assert_eq(image.verify().bytes_checked, size.to_uint64())
  }
}
