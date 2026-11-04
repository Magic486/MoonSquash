///|
/// Append-only compressed metadata stream. References are fixed when a record
/// starts, including records that span blocks. Child-first inode emission avoids
/// circular dependencies between compressed inode and directory layouts.
priv struct MetadataWriter {
  compression : Int
  encode : ((Int, Bytes) -> Bytes raise SquashError)?
  stored : Array[Byte]
  mut pending : Array[Byte]
  starts : Array[Int]
}

///|
fn metadata_writer(
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> MetadataWriter {
  { compression, encode, stored: [], pending: [], starts: [], }
}

///|
fn MetadataWriter::position(self : MetadataWriter) -> UInt64 {
  (self.stored.length().to_uint64() << 16) | self.pending.length().to_uint64()
}

///|
fn MetadataWriter::flush(self : MetadataWriter) -> Unit raise SquashError {
  if self.pending.length() == 0 {
    return
  }
  let raw = Bytes::from_array(self.pending)
  let packed = match self.encode {
    Some(encode) => encode(self.compression, raw)
    None => raw
  }
  self.starts.push(self.stored.length())
  if packed.length() > 0 && packed.length() < raw.length() {
    put16(self.stored, packed.length())
    append_bytes(self.stored, packed)
  } else {
    put16(self.stored, raw.length() | 0x8000)
    append_bytes(self.stored, raw)
  }
  self.pending = []
}

///|
fn MetadataWriter::append(
  self : MetadataWriter,
  bytes : Array[Byte],
) -> Unit raise SquashError {
  for b in bytes {
    self.pending.push(b)
    if self.pending.length() == 8192 {
      self.flush()
    }
  }
}

///|
fn MetadataWriter::mapped_reference(
  self : MetadataWriter,
  raw_offset : Int,
) -> UInt64 {
  (self.starts[raw_offset / 8192].to_uint64() << 16) |
  (raw_offset % 8192).to_uint64()
}

///|
fn compressed_metadata(
  raw : Array[Byte],
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> MetadataWriter raise SquashError {
  let writer = metadata_writer(compression, encode)
  writer.append(raw)
  writer.flush()
  writer
}

///|
fn write_compressed_index(
  output : BuildOutput,
  raw : Array[Byte],
  compression : Int,
  encode : ((Int, Bytes) -> Bytes raise SquashError)?,
) -> Int raise SquashError {
  let writer = compressed_metadata(raw, compression, encode)
  let start = output.length()
  output.append(Bytes::from_array(writer.stored))
  let index = output.length()
  for offset in writer.starts {
    output.uint64((start + offset).to_uint64())
  }
  index
}
