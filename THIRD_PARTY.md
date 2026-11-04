# Sources and implementation boundaries

The MoonBit implementation is newly authored with AI assistance. No upstream SquashFS C implementation is copied or linked.

- Linux SquashFS documentation: https://docs.kernel.org/filesystems/squashfs.html
- On-disk structure reference: https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/squashfs_fs.h (upstream GPL source, consulted for file-format definitions; not redistributed here).
- mksquashfs/unsquashfs: independent developer validation tools, not runtime dependencies.
- Node.js `fs` and `zlib`: file I/O, exclusive publication and gzip encode/decode; these are not pure MoonBit operations.
- Python standard library: POSIX scanning/extraction and `lzma`. The separate codec process loads system liblzma/liblz4/libzstd/liblzo2. These are not bundled or claimed as MoonBit algorithms; their distributions retain their upstream licenses, including GPL terms for liblzo2.
- Xattr wire layout and legacy LZMA header behavior were checked against [read_xattrs.c](https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/read_xattrs.c) and [lzma_xz_wrapper.c](https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/lzma_xz_wrapper.c). No source bodies were copied; the known-length LZMA header field is an interoperability requirement.
- MoonBit core: standard collections, encoding and JSON APIs.

All interoperability inputs are generated synthetic text/bytes; no firmware, proprietary images or server files are included. No claim of original invention of the SquashFS format.
