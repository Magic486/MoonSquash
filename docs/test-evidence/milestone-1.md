# Initial read/write milestone — 2026-11-05

Actual local Windows toolchain: moon 0.1.20260915 (2e1a46d), moonc v0.10.13+cbb11c36f. Library tests run on JS and Wasm-GC. CLI compiled to JavaScript locally and executed on Linux; this is not a claim that the Linux MoonBit native target was tested.

Linux: kernel 7.0.0-42-generic; mksquashfs 4.7.5. Test files are generated under a private project test directory, no mounts or privilege changes.

Executed `scripts/linux_oracle.py`:

| Direction/profile | Result |
|---|---|
| Official raw image → MoonSquash | 359 tree entries, 356 files read; 8 selected file/symlink byte comparisons passed |
| Official gzip image → MoonSquash | 359 tree entries, 356 files read; 8 selected file/symlink byte comparisons passed |
| MoonSquash raw builder → official unsquashfs | All 356 regular files compared byte-for-byte; symlink target, empty directory and file permission checks passed |

Fixtures include inode/directory metadata spanning 8 KiB blocks, fragments, hard-link identities, UTF-8 names, sparse and multi-block files. Builder does not yet preserve hard-link relationships: its two corresponding output files are independent files.

Independent validation found the initial writer sorted directory names using MoonBit shortlex order. Corrected to UTF-8 byte lexical ordering and added a regression test. Self-roundtrip alone had not detected this interoperability failure.

10 library test blocks cover empty image, nested files/permissions/symlink, sparse blocks, metadata boundaries, deterministic input order, byte ordering, invalid paths/duplicates, non-directory parents, truncation/header corruption, and output/traversal limits. Synthetic fixture loops are not counted as extra test blocks.

No claims yet: full adversarial validation, all compressor support, xattr/export-index validation, streaming image support, native backend, complete competition delivery, official acceptance or published CI.
