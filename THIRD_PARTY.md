# Sources and implementation boundaries

The MoonBit implementation is newly authored with AI assistance. No upstream SquashFS C implementation is copied or linked.

- Linux SquashFS documentation: https://docs.kernel.org/filesystems/squashfs.html
- On-disk structure reference: https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/squashfs_fs.h (upstream GPL source, consulted for file-format definitions; not redistributed here).
- mksquashfs/unsquashfs: independent developer validation tools, not runtime dependencies.
- Node.js `fs` and `zlib`: CLI file I/O and gzip decompression; these host operations are explicitly not pure MoonBit implementations.
- MoonBit core: standard collections, encoding and JSON APIs.

All interoperability inputs are generated synthetic text/bytes; no firmware, proprietary images or server files are included. No claim of original invention of the SquashFS format.
