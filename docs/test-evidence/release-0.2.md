# Release 0.2 validation — 2026-11-05

All fixtures are synthetic. No mounts, root changes or host device creation were used. Official tools are independent oracles; no test substitutes their implementation for MoonBit's format logic.

## Actual environments

- Windows: moon 0.1.20260915 (2e1a46d), moonc v0.10.13+cbb11c36f. JS and Wasm-GC tests, example, package and independent archive consumer.
- Linux: moon 0.1.20260920 (914d7da), moonc v0.10.14+7d59c7ec9. Sources extracted from the actual package, compiled on Linux, then tested and executed. Node v22.22.1, mksquashfs/unsquashfs 4.7.5, Python/system codecs.
- The Linux compiler emits 13 public derived-trait method-promotion deprecation warnings. These are recorded compatibility warnings, not suppressed or misreported as a warning-free build. No native MoonBit backend was tested.

## Results

| Check | Actual result |
|---|---|
| Library tests | 18 blocks pass on JS and Wasm-GC; includes 1100 attribute-bearing files, 2201 owner IDs and multi-block export/xattr indexes |
| Original raw/gzip reader oracle | 359 paths, 356 regular paths, selected payload comparisons; original builder decoded by official tools for all 356 regular files |
| Official → MoonSquash | gzip, xz, zstd, lz4, lzo, legacy LZMA: 170 paths / 169 unique inodes / 164 unique regular files; 54 fragments; 4 unique xattrs; export index checked |
| MoonSquash → official | raw and all six codecs: 173 paths / 172 unique inodes; all 164 unique regular payloads compared byte-for-byte; hard-link identity, permissions, times, binary xattrs and symlink target checked |
| Layout-independent diff | No changes between semantically equal compressor variants; unit tests detect content, mode and hard-link-group changes |
| Safe extraction | 164 regular objects, one hard link, symlink and user xattrs preserved; existing destinations refused; special objects reported rather than created |
| Host regression | Existing/symlink image outputs refused without altering originals; mode-000 directories/files and hard links preserved; packing output inside source refused |
| Directory packing | Host ownership, hard-link identity, root mtime and four xattrs preserved; official extraction payload comparison passed |
| Large official directory | 1101 inodes, including long directory/index records, verified |
| Malformed images | 17 explicit corrupt-header/reference/table/data/truncation cases rejected; not counted as separate library tests or a fuzz-proof claim |
| Actual archive consumer | Separate workspace imports extracted local ZIP and exercises build/read/range/attributes/hardlinks/verify/diff on JS and Wasm-GC |

Reproduction: `moon test --target js`, `moon test --target wasm-gc`; `python3 scripts/linux_oracle.py scripts/moonsquash.cjs`; `python3 scripts/full_oracle.py scripts/moonsquash.cjs`; `python3 scripts/host_regressions.py scripts/moonsquash.cjs`; `moon package` and `scripts/package_consumer.py`.

Independent checks found real interoperability defects: default shortlex versus required byte-name sorting (M1), and legacy LZMA's required known-length header (0.2). Host tests also cover final metadata application after creating hard links and children of restrictive directories.

## Evidence boundaries

No live firmware or confidential host snapshot is included. No claim of exhaustive adversarial proof, cryptographic validation, kernel mount validation, arbitrary-size filesystem support or complete official-tool option parity. Public CI, registry consumption, publication and official acceptance have not occurred. Exact profile limits are in README.
