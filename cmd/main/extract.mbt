///|
fn attrs_json(attrs : Array[@squash.Xattr]) -> Json {
  Json::array(
    attrs.map(a => {
      Json::object({
        "name": @json.to_json(a.name.iter().map(b => b.to_int()).to_array()),
        "value": @json.to_json(a.value.iter().map(b => b.to_int()).to_array()),
      })
    }),
  )
}

///|
extern "js" fn prepare_stage(destination : String) -> String? =
  #| destination => { try { const fs=require('node:fs'),p=require('node:path'); if(fs.existsSync(destination))return undefined; return fs.mkdtempSync(p.join(p.dirname(p.resolve(destination)),'.moonsquash-')); } catch { return undefined; } }

///|
extern "js" fn stage_chunk(stage : String, id : Int, bytes : Bytes) -> Bool =
  #| (stage,id,bytes) => { try {require('node:fs').appendFileSync(require('node:path').join(stage,String(id)),bytes,{mode:0o600});return true;}catch{return false;} }

///|
extern "js" fn finish_extract(
  stage : String,
  destination : String,
  plan : String,
) -> String? =
  #| (stage,destination,plan) => { try {const helper=process.env.MOONSQUASH_HOST;if(!helper)return undefined;
  #| const r=require('node:child_process').spawnSync(process.env.PYTHON||'python3',[helper,'extract',stage,destination],{input:plan,maxBuffer:16777216,timeout:300000});
  #| if(r.status!==0){if(r.stderr)process.stderr.write(r.stderr);return undefined;}return r.stdout.toString();}catch{return undefined;} }

///|
extern "js" fn clean_stage(stage : String) -> Unit =
  #| stage => require('node:fs').rmSync(stage,{recursive:true,force:true})

///|
fn extract_command(image : @squash.Image, destination : String) -> Unit raise {
  // Validate before any destination writes. The staging directory is private.
  ignore(image.verify())
  guard prepare_stage(destination) is Some(stage) else {
    fail("extract needs a new destination in an existing writable parent")
  }
  defer clean_stage(stage)
  let entries : Array[Json] = []
  let stored : Map[Int, Bool] = Map([])
  let mut total = 0UL
  for e in image.tree() {
    let node = e.inode
    let kind = if node.kind > 7 { node.kind - 7 } else { node.kind }
    let values : Map[String, Json] = {
      "path": @json.to_json(e.path),
      "inode": @json.to_json(node.number),
      "kind": @json.to_json(kind),
      "mode": @json.to_json(node.mode),
      "uid": @json.to_json(node.uid),
      "gid": @json.to_json(node.gid),
      "mtime": @json.to_json(node.mtime),
      "xattrs": attrs_json(image.xattrs(node)),
    }
    match node.content {
      File(_, size, _, _, _) =>
        if !stored.contains(node.number) {
          total += size.to_uint64()
          guard total <= 4294967296UL else {
            fail("extraction exceeds 4 GiB output budget")
          }
          stored[node.number] = true
          guard stage_chunk(stage, node.number, b"") else {
            fail("cannot stage file")
          }
          let mut at = 0
          while at < size {
            let n = Int::min(1048576, size - at)
            guard stage_chunk(stage, node.number, image.read_range(node, at, n)) else {
              fail("cannot stage file data")
            }
            at += n
          }
        }
      Symlink(target) =>
        values["target"] = @json.to_json(
          target.iter().map(b => b.to_int()).to_array(),
        )
      Device(number) => values["device"] = @json.to_json(number)
      _ => ()
    }
    entries.push(Json::object(values))
  }
  guard finish_extract(stage, destination, Json::array(entries).stringify())
    is Some(report) else {
    fail("extraction host operation failed")
  }
  println(report)
}
