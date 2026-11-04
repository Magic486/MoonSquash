///|
/// Reject ambiguity and unrecognized fields before reading source payloads.
fn validate_spec(spec : Json) -> Unit raise {
  guard spec is Object(top) else { fail("specification must be an object") }
  for key, value in top {
    match key {
      "entries" => {
        guard value is Array(_) else { fail("entries must be an array") }
      }
      "compression" => {
        guard value is String(_) else { fail("compression must be a string") }
      }
      "fragments" | "exportable" | "metadata_compression" => {
        guard value is True || value is False else {
          fail("\{key} must be boolean")
        }
      }
      "block_size" | "created" => ignore(uint_field(spec, key, 0U))
      _ => fail("unknown specification field: \{key}")
    }
  }
  guard top.get("entries") is Some(Array(items)) else {
    fail("entries are required")
  }
  for item in items {
    guard item is Object(fields) else { fail("entry must be an object") }
    let mut types = 0
    for key, value in fields {
      match key {
        "path" => {
          guard value is String(_) else { fail("path must be a string") }
        }
        "source" | "symlink" | "hardlink" | "device" => {
          guard value is String(_) else { fail("\{key} must be a string") }
          types += 1
        }
        "directory" | "fifo" | "socket" => {
          guard value is True else { fail("\{key} must be true") }
          types += 1
        }
        "uid" | "gid" | "mtime" | "mode" | "number" =>
          ignore(uint_field(item, key, 0U))
        "xattrs" => {
          guard value is Object(attrs) else { fail("xattrs must be an object") }
          for attr in attrs.values() {
            match attr {
              String(_) => ()
              Object(source) => {
                guard source.length() == 1 &&
                  source.get("source") is Some(String(_)) else {
                  fail("xattr source must contain only a source filename")
                }
              }
              _ => fail("xattr must be text or source object")
            }
          }
        }
        _ => fail("unknown entry field: \{key}")
      }
    }
    guard types == 1 else {
      fail("entry must declare exactly one content type")
    }
    if fields.contains("number") && !fields.contains("device") {
      fail("number is only valid for devices")
    }
    if fields.contains("hardlink") {
      for key in ["uid", "gid", "mtime", "mode", "xattrs"] {
        guard !fields.contains(key) else {
          fail("hard-link metadata must be specified on target: \{key}")
        }
      }
    }
  }
}
