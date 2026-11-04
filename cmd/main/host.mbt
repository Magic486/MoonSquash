///|
extern "js" fn codec_host(
  mode : String,
  id : Int,
  data : Bytes,
  limit : Int,
) -> Bytes? =
  #| (mode,id,data,limit) => { try {
  #|   if (id === 1) { const z=require('node:zlib'); return new Uint8Array(mode==='encode' ? z.deflateSync(data,{level:9}) : z.inflateSync(data,{maxOutputLength:limit})); }
  #|   const helper=process.env.MOONSQUASH_CODEC; if (!helper) return undefined;
  #|   const r=require('node:child_process').spawnSync(process.env.PYTHON || 'python3',[helper,mode,String(id),String(limit)],{input:Buffer.from(data),maxBuffer:limit+65536,timeout:30000});
  #|   if(r.status!==0) { if(r.stderr) process.stderr.write(r.stderr); return undefined; }
  #|   return new Uint8Array(r.stdout);
  #| } catch { return undefined; } }

///|
extern "js" fn open_fd(path : String) -> Int =
  #| path => { try { const fs=require('node:fs'); const fd=fs.openSync(path,'r'); const st=fs.fstatSync(fd); if(!st.isFile()||st.size>2147483647) {fs.closeSync(fd);return -1;} return fd; } catch { return -1; } }

///|
extern "js" fn fd_size(fd : Int) -> Int =
  #| fd => require('node:fs').fstatSync(fd).size

///|
extern "js" fn read_at(fd : Int, at : Int, size : Int) -> Bytes? =
  #| (fd,at,size) => { try { const fs=require('node:fs'),b=Buffer.alloc(size); let n=0; while(n<size) {const k=fs.readSync(fd,b,n,size-n,at+n);if(!k)return undefined;n+=k;}return new Uint8Array(b); } catch {return undefined;} }

///|
extern "js" fn close_fd(fd : Int) -> Unit =
  #| fd => require('node:fs').closeSync(fd)

///|
fn source(fd : Int) -> @squash.Image raise @squash.SquashError {
  @squash.open_source(
    fd_size(fd),
    (at, size) => {
      guard read_at(fd, at, size) is Some(b) else {
        raise @squash.Invalid(at, "source read failed")
      }
      b
    },
    decode~,
  )
}

///|
fn encode(id : Int, data : Bytes) -> Bytes raise @squash.SquashError {
  guard codec_host("encode", id, data, 2097152) is Some(b) else {
    raise @squash.Unsupported("compressor unavailable or failed: \{id}")
  }
  b
}
