# 0.3.2 strict review and server revalidation

2026-11-26. Revalidated from transferred source in an isolated directory on the authorized Linux server. No mounts, privileged restoration or host configuration changes. This is technical evidence, not official contest acceptance.

## Defects and regression evidence

| Gap | Fix / evidence |
| --- | --- |
| CLI zlib decoder accepted a complete stream followed by garbage inside its declared extent | Require the decoder to consume the entire input. A fixed-size raw extent is replaced with a valid compressed stream plus garbage; offsets remain unchanged. Baseline accepted, 0.3.2 rejects. |
| Extended inode sparse count could disagree with zero block descriptors | Compare the declared count with logical bytes represented by zero descriptors, including partial final blocks. Baseline accepted a nonzero count for a dense file, 0.3.2 rejects. Valid empty/full/partial sparse files pass. |
| Random source header callback did not enforce exact length | Reject short/oversized header results, and reject a source shorter than 96 bytes before invoking its callback. Regression fails on the original implementation. |
| lookup omitted the directory entry identity checks used by tree | Validate inode number and basic type on each path component. A directory entry with a changed type is rejected. |
| Archive consumer hard-coded an old version | Read version from the actual ZIP manifest; provide a separate `--registry VERSION` mode without a workspace override. |

## Environments and actual results

Windows: moon 20260915 / moonc v0.10.13. Linux: moon 20260920 / moonc v0.10.14, Node 22.22.1, Python 3.14.4, squashfs-tools 4.7.5. Linux retains 13 documented derived-trait promotion warnings; checks are successful, not warning-free. Public latest-toolchain CI results belong to the release record.

| Check | Result |
| --- | --- |
| Check/build, public interface generation and compatible formatting | Pass; public library signatures unchanged |
| JS / Wasm-GC library tests | 24 / 24 pass on each backend, on both Windows and Linux |
| Runnable Wasm-GC example | Pass on server |
| Basic oracle | Raw/gzip reads and official extraction of generated image pass |
| Full codec oracle | gzip, xz, zstd, lz4, lzo, legacy LZMA official-to-MoonSquash and MoonSquash-to-official; raw output also tested; 164 unique regular payloads per fixture |
| Host workflows | Directory pack; safe extract; hardlinks, attributes, zero permissions, symlink/output refusal; 1100-file directory |
| Malformed images | Existing 17 mutations plus 5 strict cases all rejected; the latter include 2 new baseline acceptances |
| Invalid specifications | 8 rejected |
| Scale | 210845000 unique payload bytes, 2429 paths, 2403 regular paths compared; deterministic output; empty semantic diff against official image and raw-metadata variant |
| Public OpenWrt 24.10.0 x86-64 image | Published checksum matched; 1225 regular file payloads, 224 symlink targets and 113 non-root directories compared; special/privileged operations omitted and reported |
| Actual ZIP consumer | New 0.3.2 archive independently imported and run on JS and Wasm-GC on both Windows and Linux |

Scale is synthetic, not a second real distribution. One server run: streaming build 1.38 s / 159936 KiB peak RSS; verify 5.56 s / 157428 KiB; semantic diff 20.04 s / 166576 KiB. These are observations, not portable performance guarantees. The compressed image has 9134951 bytes.

## Reproduce

Use README commands, including all oracle scripts. For the larger synthetic fixture:

```sh
MOONSQUASH_SCALE_MIB=192 python3 scripts/scale_oracle.py scripts/moonsquash.cjs scripts/host.py
moon package
python3 scripts/package_consumer.py _build/publish/Magic486-moonsquash-0.3.2.zip
# Only after the version exists in the public registry:
python3 scripts/package_consumer.py --registry 0.3.2
```

`review_image_cases.py --baseline` prints unexpected acceptances instead of asserting; it is for comparison against old code, never the passing CI mode. Ordinary invocation requires all cases to be rejected.

## Boundaries

Image offsets and single files remain below 2 GiB; string paths require UTF-8; privileged extraction is intentionally omitted; no native backend, kernel-mount certification or exhaustive fuzz claim. One real OpenWrt image plus synthetic codec/scale matrices do not establish compatibility with every firmware. Registry publication and final CI are recorded separately in [release.md](../release.md).
