# MoonSquash

**SquashFS 4 filesystem image library and CLI implemented in MoonBit.** Version 0.3.0 is prepared for the November 2026 hackathon. It reads, builds, packs, extracts, verifies and compares images without mounting them or running official image tools at runtime.

Use it to inspect firmware and read-only Linux distributions, build reproducible application images, and explain changes between images. This is not a claim of complete `squashfs-tools` option parity or official contest acceptance.

## Capabilities

| Area | Implemented |
|---|---|
| Reading | SquashFS 4.0 little endian; all 14 basic/extended inode types; metadata streams; directories; sparse files; fragments; UID/GID; symlinks; hard-link identity |
| Attributes | `user.*`, `trusted.*`, `security.*`; binary values; inline/out-of-line reads; inline writes; NFS export index reads/writes |
| Building | Deterministic byte-sorted layout, automatic parents, root metadata, owners/modes/times, hard links, special records, sparse blocks and tail packing |
| Compression | Raw, gzip, xz, zstd, lz4, lzo and legacy LZMA; compressed metadata/data reading and writing, with per-block raw fallback |
| Access | In-memory API or bounded random-access callback; partial-file reads; chunked CLI file output |
| Verification | Table boundaries, pointer continuity, complete inode-record coverage, references, parent/type/link counts, directory names/order/cycles, data, fragments, IDs, xattrs and export mappings |
| Difference | Added/removed/type/content/target/device/mode/owner/time/xattr/hard-link-group changes, independent of physical layout |
| Host workflow | Streaming directory packing, safe ordinary-file extraction, exclusive atomic image publication |

The core never invokes `mksquashfs` or `unsquashfs`. Node supplies I/O and gzip; Python supplies standard compression libraries and POSIX operations. See [implementation boundaries](THIRD_PARTY.md).

## Quick start

Requires MoonBit and Node.js. Linux packing/extraction and non-gzip codecs additionally need Python 3.9+ and system liblzma/liblz4/libzstd/liblzo2 as applicable. Debian/Ubuntu packages: `python3`, `liblzma5`, `liblz4-1`, `libzstd1`, `liblzo2-2`. Official tools are only test dependencies.

```sh
moon check --target js
moon test --target js
moon test --target wasm-gc
moon build --target js
moon run examples/basic --target wasm-gc
node scripts/moonsquash.cjs pack input-directory image.sqfs gzip
node scripts/moonsquash.cjs info image.sqfs
node scripts/moonsquash.cjs tree image.sqfs
node scripts/moonsquash.cjs cat image.sqfs /etc/example.conf
node scripts/moonsquash.cjs xattrs image.sqfs /etc/example.conf
node scripts/moonsquash.cjs verify image.sqfs
node scripts/moonsquash.cjs extract image.sqfs new-directory
node scripts/moonsquash.cjs diff before.sqfs after.sqfs
```

`info`, `tree`, `xattrs`, `verify`, `diff`, and `extract` emit JSON. Xattr names/values are byte arrays; UInt64 totals are strings. `cat` emits bytes and does not follow symlinks. Differences are data: `diff` exits 0 when changes exist; errors exit 1. Outputs must be new paths. Put `pack` output outside the source tree and keep sources unchanged while reading/packing.

Use the launcher above to locate adapters. Generated `main.js` alone handles gzip but needs `MOONSQUASH_CODEC` and `MOONSQUASH_HOST` paths for other host operations. `PYTHON` selects a Python executable.

## Specification-driven build

```json
{"compression":"gzip","block_size":131072,"created":0,"entries":[
  {"path":"/","directory":true,"mode":493,"uid":1000,"gid":1000},
  {"path":"/app/readme","source":"README.md","mode":420,"uid":1000,"gid":1000,
   "xattrs":{"user.origin":"MoonSquash"}},
  {"path":"/alias","hardlink":"/app/readme"},
  {"path":"/link","symlink":"app/readme"},
  {"path":"/empty","directory":true}
]}
```

```sh
node scripts/moonsquash.cjs build spec.json image.sqfs
```

Modes are decimal (420 = 0644, 493 = 0755). Source paths are relative to the working directory. Binary xattrs use `{"source":"value.bin"}`. Other entries: `fifo:true`, `socket:true`, or `device:"char"|"block"` with encoded SquashFS device `number`. Links inherit target metadata. Compressors: `none`, `gzip`, `xz`, `zstd`, `lz4`, `lzo`, `lzma`; options include `fragments:false`, `exportable:false` and `metadata_compression:false`. CLI compression defaults to gzip; the library defaults to raw data without an encoder callback.

## Library and package

See [public API](pkg.generated.mbti) and [runnable example](examples/basic/main.mbt). `open_source` accepts a stable random-access source; `build_image` accepts memory entries; `build_to` accepts `External(size)` entries and bounded read/random-write callbacks. CLI construction uses `build_to`. JS and Wasm-GC library backends are tested; the CLI is JS and POSIX packing/extraction is tested on Linux.

```sh
moon package
python3 scripts/package_consumer.py _build/publish/Magic486-moonsquash-0.3.0.zip
```

Repository: [Magic486/MoonSquash](https://github.com/Magic486/MoonSquash). Package identity: `Magic486/moonsquash@0.3.0`; published on [Mooncakes](https://mooncakes.io/docs/Magic486/moonsquash@0.3.0). Installation validation is recorded in [release notes](docs/release.md). The archive consumer extracts the actual ZIP into a separate workspace.

## Independent validation

```sh
python3 scripts/linux_oracle.py scripts/moonsquash.cjs
python3 scripts/full_oracle.py scripts/moonsquash.cjs
python3 scripts/host_regressions.py scripts/moonsquash.cjs
python3 scripts/review_spec_cases.py scripts/moonsquash.cjs
python3 scripts/review_image_cases.py scripts/moonsquash.cjs
python3 scripts/scale_oracle.py scripts/moonsquash.cjs scripts/host.py
```

Tests generate synthetic fixtures and compare official tools in both directions. The full matrix needs `squashfs-tools` with all six compressors. A separate published OpenWrt image checks a real distribution layout (1225 regular files and 224 symlinks):

```sh
mkdir -p .local
curl --fail --location https://downloads.openwrt.org/releases/24.10.0/targets/x86/64/openwrt-24.10.0-x86-64-generic-squashfs-rootfs.img.gz -o .local/openwrt-rootfs.img.gz
python3 scripts/distribution_oracle.py scripts/moonsquash.cjs .local/openwrt-rootfs.img.gz
```

That script checks the pinned published SHA-256 before processing; the image is not included in the package or executed. No mounts, root, host device creation or configuration changes are used. See [evidence](docs/test-evidence/review-0.3.md) and [acceptance review](docs/acceptance-review.md).

## Deliberate boundaries

- Image offsets and file sizes are below 2 GiB. Random-access input avoids loading the whole image. Caches retain at most 128 metadata blocks, 16 data blocks and one file's block-offset index.
- String paths require UTF-8, depth is limited to 128 and tree traversal defaults to 100000 entries. Raw names are available via `entries`. Raw symlink payloads are supported by the library.
- Builder: at most 10000 explicit entries, 20000 expanded nodes and 16 MiB xattr encoding. The convenience `build_image` retains a 128 MiB payload limit. `build_to` and the CLI stream file payloads and output; the default aggregate payload budget is 4 GiB, while physical image offsets and each file remain below 2 GiB. Metadata/inode lists remain in memory. No automatic identical-file deduplication is claimed.
- `read_file` defaults to 64 MiB output; `read_range` allows 16 MiB per call. Extraction has a 4 GiB aggregate regular-data budget and 16 MiB plan budget.
- Safe extraction preserves ordinary permissions, times, user xattrs, hard links and symlinks. It does not follow image symlinks, create device/FIFO/socket nodes, change ownership, or apply privileged modes/xattrs. JSON lists omitted operations. Outward/absolute symlinks may be preserved as links. An I/O failure may leave a partial new extraction directory.
- Verification has a default 4 GiB decoded-data budget (configurable via the library API) and checks compressor options, directory indexes and data-area overlaps. It is structural/semantic within this profile; it is not cryptographic authenticity, kernel mount certification, exhaustive fuzz proof or repair. Legacy LZMA support targets image tools, not current kernels.

Validated compilers: Windows moonc v0.10.13 / moon 20260915; Linux moonc v0.10.14 / moon 20260920. The latter reports a public derived-trait promotion deprecation; compilation/tests succeed. Current CI uses the latest compiler and reports formatter migrations as warnings to retain September source compatibility. No native-backend claim is made.

Apache-2.0. [Architecture](docs/architecture.md) · [demo](docs/demo.md) · [release status](docs/release.md) · [submission draft](submission-proposal.md).

The stricter 0.3 review found and fixed three malformed-image acceptance bugs and eight ambiguous/lossy specification cases. See [review findings and remaining submission risks](docs/strict-review.md). Scale measurements use synthetic fixtures; the separate OpenWrt check uses an actual public distribution image.
