// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "local/moonsquash"

version = "0.3.0"

readme = "README.md"

repository = ""

license = "Apache-2.0"

keywords = [ "squashfs", "filesystem", "linux", "image" ]

preferred_target = "wasm-gc"

description = "SquashFS 4 filesystem image toolkit in MoonBit"
