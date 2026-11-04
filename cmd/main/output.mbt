///|
extern "js" fn new_output(path : String) -> Int =
  #| path => {try{return require('node:fs').openSync(path,'wx+',0o644);}catch{return -1;}}

///|
extern "js" fn output_write(fd : Int, at : Int, data : Bytes) -> Bool =
  #| (fd,at,data) => {try {const fs=require('node:fs');let n=0;while(n<data.length){const k=fs.writeSync(fd,data,n,data.length-n,at+n);if(!k)return false;n+=k;}return true;}catch{return false;}}

///|
extern "js" fn publish_output(
  fd : Int,
  temporary : String,
  destination : String,
) -> Bool =
  #| (fd,temporary,destination) => {try{const fs=require('node:fs');fs.fsyncSync(fd);fs.linkSync(temporary,destination);return true;}catch{return false;}}
