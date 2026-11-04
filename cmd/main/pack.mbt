///|
extern "js" fn scan_host(
  source : String,
  stage : String,
  compression : String,
) -> String? =
  #| (source,stage,compression) => {try {const helper=process.env.MOONSQUASH_HOST;if(!helper)return undefined;
  #| const r=require('node:child_process').spawnSync(process.env.PYTHON||'python3',[helper,'scan',source,stage,compression],{maxBuffer:16777216,timeout:300000});
  #| if(r.status!==0){if(r.stderr)process.stderr.write(r.stderr);return undefined;}return r.stdout.toString();}catch{return undefined;}}

///|
fn pack_command(
  input : String,
  output : String,
  compression : String,
) -> Unit raise {
  guard prepare_stage(output) is Some(stage) else {
    fail("pack needs a new output path")
  }
  defer clean_stage(stage)
  guard scan_host(input, stage, compression) is Some(spec) else {
    fail("directory scan failed")
  }
  let spec_path = stage + "/spec.json"
  guard write_new(spec_path, @utf8.encode(spec)) else {
    fail("cannot stage build specification")
  }
  build_command(spec_path, output)
}
