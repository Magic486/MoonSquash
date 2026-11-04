# Architecture and invariants

The implementation models the SquashFS 4 disk format directly. Standard compression libraries and host filesystem syscalls are the adapter boundary; official image tools are independent test oracles.

## Reader

`open_source(length, read, decode)` checks the superblock and every physical range against `bytes_used`. The callback must return exactly the requested bytes and keep its source immutable. `open_image` uses the same contract over memory.

Metadata consists of 8 KiB decoded blocks with two-byte stored-length/raw headers. Inode references combine relative metadata block addresses and decoded offsets. A bounded cache serves repeated inode/ID access. All fourteen wire types are decoded. Tree traversal cross-checks directory entry identity/type and rejects cycles, unsafe names and non-UTF-8 string paths; raw entry names remain available.

File descriptors encode compressed/raw/sparse blocks; tails refer to shared indexed fragments. `read_range` builds one file's checked prefix-offset index and only decodes overlapping blocks. A sixteen-block data cache avoids repeated tail decompression. Xattrs have indexed lists and inline/out-of-line values, preserved as bytes. Export indexes independently resolve inode numbers.

## Builder

Canonical paths are byte-sorted, implicit parents inserted, hard-link chains resolved and unique inodes numbered. Owners are interned and xattr IDs allocated. Cycles, missing targets and directory hard links are errors.

The data pass compresses only when smaller than raw, emits sparse blocks, and packs tails. A layout pass fixes inode and directory references. Metadata is written in raw blocks to keep references stable without a compression/layout feedback loop. This is a valid profile, with larger metadata as the explicit tradeoff. The builder then emits fragment/export/ID/xattr tables and the superblock.

Xattr output is inline; input also supports official out-of-line sharing. Special files are disk records, not host devices. Hard links share records/link counts. Independently supplied equal files stay independent.

## Validation and diff

Verification checks table extents/continuity, indexed lengths, metadata boundaries, the complete inode stream, reference starts/reachability, directory parent/type/link counts, name ordering, file decoding, fragments, IDs, xattrs and export mappings. Errors carry a reason/offset; no repair/authenticity claim is made.

Diff compares paths, bounded file ranges, metadata, attributes and link groups. On-disk inode numbers and physical compression/layout are not filesystem changes.

## Host boundary

Node handles file I/O, gzip and exclusive output publication. Python calls standard compression libraries and implements filesystem scanning/extraction; it does not parse images. Extraction applies a verified plan in a new private root, uses no-follow parent descriptors and exclusive file creation, and reports privileged operations it does not perform.

For new features, add an independent official fixture and a failure case before expanding claims. Retain no-follow/exclusive-output regressions for host changes. The candidate should be able to explain reference encoding, fragments, hard-link identities and why self-roundtrip alone missed directory sorting and legacy LZMA issues.
