# Three-minute demonstration

Build on Linux with `moon build --target js`. Use generated example files, one hard link, a symlink and a user xattr. Keep image output outside the source directory.

1. **0:00-0:40:** Run `node scripts/moonsquash.cjs pack input demo.sqfs gzip`, then `info` and `tree`. Explain the MoonBit format core and disclosed codec boundary.
2. **0:40-1:20:** Run `cat`, `xattrs`, `verify`. Show a shared inode for the hard-link pair. Compare with `unsquashfs -lln demo.sqfs`.
3. **1:20-2:00:** Run `extract demo.sqfs new-output`, explain preserved metadata and omitted privileges. Change one source, create a new image, run `diff` and explain its reasons.
4. **2:00-3:00:** Run `moon run examples/basic --target wasm-gc`; show the six-codec oracle, streaming scale results and independent archive consumer results. State the size/UTF-8/host-codec boundaries and unpublished status.

Use no private firmware or real server configuration. Test counts are evidence of specific checks, not an official acceptance threshold.
