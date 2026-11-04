# MoonSquash

MoonBit SquashFS 4 filesystem image toolkit. **Development milestone, not a complete release or submission.**

Image semantics are implemented in MoonBit. The Node CLI supplies filesystem I/O and gzip decompression through Node zlib. Official `mksquashfs`/`unsquashfs` are used only for independent tests.

## Implemented

- SquashFS 4.0 superblock, bounded metadata traversal, basic/extended inode models, directories and UID/GID lookup.
- Regular files, sparse blocks, fragments, hard-link identity and symlink contents; device/FIFO/socket type models.
- Raw blocks and pluggable bounded decompression; CLI gzip adapter.
- Deterministic uncompressed builder for files, folders and symlinks, including sparse blocks and metadata spanning multiple blocks.
- CLI `info`, `tree`, `cat`, `verify`, `build`; library tests on JS and Wasm-GC.

## Build and use

Validated toolchain: moon 0.1.20260915, moonc v0.10.13+cbb11c36f. The CLI requires Node.js.

```sh
moon check --target js
moon test --target js
moon test --target wasm-gc
moon build --target js
node _build/js/debug/build/cmd/main/main.js info input.sqfs
node _build/js/debug/build/cmd/main/main.js tree input.sqfs
node _build/js/debug/build/cmd/main/main.js cat input.sqfs /etc/example.conf
node _build/js/debug/build/cmd/main/main.js verify input.sqfs
```

`cat` emits raw file bytes or a symlink target without following it. `tree` emits JSON. Errors go to stderr and exit 1. `verify` checks the reachable tree and reads file data; it is **not yet a full filesystem checker**.

To build an image, save this JSON spec. Host `source` paths are relative to the working directory; `path` is absolute inside the image:

```json
{"entries":[
  {"path":"/app/readme.txt","source":"README.md"},
  {"path":"/empty","directory":true},
  {"path":"/readme","symlink":"app/readme.txt"}
]}
```

```sh
node _build/js/debug/build/cmd/main/main.js build spec.json new-image.sqfs
unsquashfs -d new-output new-image.sqfs
```

The CLI uses root ownership, zero timestamps and default modes 0644/0755/0777. Library callers can choose permissions and creation time. Existing output paths are refused. Writes are not atomic; an I/O failure can leave partial output.

## Independent Linux verification

```sh
python3 scripts/linux_oracle.py _build/js/debug/build/cmd/main/main.js
```

Requires Node.js, Python 3, mksquashfs and unsquashfs. Generates synthetic files in a temporary directory beside the CLI and cleans that directory on exit. No mounts or privileged operations. See [actual test evidence](docs/test-evidence/milestone-1.md).

## Limits and remaining scope

The reader holds the entire image in memory and uses checked Int-sized offsets below 2 GiB. CLI input is limited to 512 MiB; file reads default to 64 MiB output, metadata reads to 16 MiB, tree depth to 128 and traversal to 100000 entries. Raw directory APIs expose filename bytes; string path APIs require UTF-8. Symlinks are not automatically followed.

Builder profile: at most 10000 input entries / 20000 expanded nodes and 128 MiB file data; uncompressed output, no fragment packing, xattrs, export index or hard-link deduplication. Ownership is root. Compressed reading requires a decoder; built-in CLI support currently covers gzip only.

Still required: compressed construction and fragment packing; xattrs/export indexes; hard-link and ownership preservation; bounded random-access I/O; safe extraction; richer structural validation; image diff; more compression adapters and malformed-image regressions. These are plans, not implemented claims. See [project scope](project-proposal.md).

`local/moonsquash` is a development placeholder. No remote repository, registry release or official submission has been made. Apache-2.0; see [third-party disclosure](THIRD_PARTY.md).
