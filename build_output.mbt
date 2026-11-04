///|
/// Random-write output: sequential body followed by one 96-byte header patch.
priv struct BuildOutput {
  mut position : Int
  write : (Int, Bytes) -> Unit raise SquashError
}

///|
fn BuildOutput::length(self : BuildOutput) -> Int {
  self.position
}

///|
fn BuildOutput::append(
  self : BuildOutput,
  bytes : Bytes,
) -> Unit raise SquashError {
  guard bytes.length() <= 2147483647 - self.position else {
    raise Limit("image exceeds 2 GiB profile")
  }
  (self.write)(self.position, bytes)
  self.position += bytes.length()
}

///|
fn BuildOutput::uint(
  self : BuildOutput,
  value : UInt,
) -> Unit raise SquashError {
  let b : Array[Byte] = []
  put32(b, value)
  self.append(Bytes::from_array(b))
}

///|
fn BuildOutput::uint64(
  self : BuildOutput,
  value : UInt64,
) -> Unit raise SquashError {
  self.append(value.to_le_bytes())
}

///|
/// Build a materialized image with a 128 MiB aggregate payload limit.
pub fn build_image(
  entries : Array[BuildEntry],
  block_size? : Int = 131072,
  created? : UInt = 0U,
  attributes? : Map[String, BuildMetadata] = Map([]),
  compression? : Int = 1,
  encode? : ((Int, Bytes) -> Bytes raise SquashError)? = None,
  fragments? : Bool = true,
  exportable? : Bool = true,
  metadata_compression? : Bool = true,
) -> Bytes raise SquashError {
  let bytes : Array[Byte] = []
  let output : BuildOutput = {
    position: 0,
    write: (at, data) => {
      if at == bytes.length() {
        append_bytes(bytes, data)
      } else {
        guard at == 0 && data.length() == 96 && bytes.length() >= 96 else {
          raise Invalid(at, "invalid header patch")
        }
        for i in 0..<96 {
          bytes[i] = data[i]
        }
      }
    },
  }
  ignore(
    build_internal(
      entries,
      output,
      None,
      134217728UL,
      block_size~,
      created~,
      attributes~,
      compression~,
      encode~,
      fragments~,
      exportable~,
      metadata_compression~,
    ),
  )
  Bytes::from_array(bytes)
}

///|
/// Build to a random-write sink without retaining file payload or image bytes.
/// External(size) entries are read by image path, offset and requested length.
/// Sources must remain stable; callbacks may fail. Publish only after success.
pub fn build_to(
  entries : Array[BuildEntry],
  write : (Int, Bytes) -> Unit raise SquashError,
  read : (String, Int, Int) -> Bytes raise SquashError,
  block_size? : Int = 131072,
  created? : UInt = 0U,
  attributes? : Map[String, BuildMetadata] = Map([]),
  compression? : Int = 1,
  encode? : ((Int, Bytes) -> Bytes raise SquashError)? = None,
  fragments? : Bool = true,
  exportable? : Bool = true,
  metadata_compression? : Bool = true,
  max_data? : UInt64 = 4294967296UL,
) -> Superblock raise SquashError {
  let output : BuildOutput = { position: 0, write, }
  build_internal(
    entries,
    output,
    Some(read),
    max_data,
    block_size~,
    created~,
    attributes~,
    compression~,
    encode~,
    fragments~,
    exportable~,
    metadata_compression~,
  )
}

///|
fn payload_size(content : BuildContent) -> Int {
  match content {
    Regular(bytes) => bytes.length()
    External(size) => size
    _ => 0
  }
}

///|
fn flush_fragment(
  output : BuildOutput,
  tail : Array[Byte],
  records : Array[Byte],
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> Unit raise SquashError {
  if tail.length() == 0 {
    return
  }
  let at = output.length()
  let descriptor = store_block(
    output,
    Bytes::from_array(tail),
    compression,
    encode,
  )
  put64(records, at.to_uint64())
  put32(records, descriptor)
  put32(records, 0U)
}
