# Strict review / release 0.3 evidence

Date: 2026-11-05. This extends, rather than rewrites, [0.2 evidence](release-0.2.md). Generated matrix/scale fixtures are synthetic; a separate public OpenWrt image tests real distribution data. No mounts, privilege changes or host device creation were used. Official image tools are test oracles only.

## Environment and checks

Windows moon 20260915 / moonc v0.10.13; Linux moon 20260920 / moonc v0.10.14, Node 22.22.1, squashfs-tools 4.7.5. The Linux compiler still emits the 13 previously documented public derived-trait promotion deprecations; checks pass, not warning-free. No native-backend claim.

| Check | Observed result |
|---|---|
| Library | 21 test blocks pass on JS and Wasm-GC; Linux builds from extracted source |
| Compressed-reference regression | 1100 attribute-bearing files, 2201 owner IDs, cross-block inode/directory/ID/export/xattr metadata and hardlink alias; both backends |
| Streaming regression | Reads bounded by configured block size; streaming output equals memory output; short source rejected; actual archive consumer imports streaming API |
| Verification budget | 8192 bytes accepted with 8192 budget and rejected with 4096 budget |
| Official → MoonSquash | All six codecs: 170 paths, 169 inodes, 164 unique regular files, 54 fragments, 4 xattrs; export verified |
| MoonSquash → official | Raw plus six codecs, now with compressed metadata; all 164 regular payloads compared and metadata/links checked by existing full oracle |
| Host behavior | Safe extraction, restrictive permissions, existing/symlink output refusal and packing-output placement regressions |
| Corrupt images | Existing 17 cases plus 3 newly reproduced validator defects; all rejected after fixes |
| Invalid build specs | 8 formerly accepted cases now rejected before publication |
| Distribution | Actual 0.3 ZIP imported into an independent JS/Wasm-GC consumer; memory and streaming APIs exercised |
| Public OpenWrt image | 1564 entries; 1225 regular payloads and 224 symlinks match official extraction; one device record is reported without creation |

The backend-neutral compressed-reference unit test explicitly uses an in-process codec stub to force block-reference remapping. It is not a real-compressor compatibility result. Real gzip/xz/zstd/lz4/lzo/LZMA compatibility is separately tested against official tools.

## Before/after defect reproduction

`scripts/review_spec_cases.py` tests conflicting source/directory selectors, a non-object xattr collection, non-string compression, non-boolean fragment/export options, an unknown misspelled field and hardlink-owned metadata. Against baseline 0.2, all 8 were unexpectedly accepted. Current result:

```json
{"invalid_specifications":8,"unexpectedly_accepted":[]}
```

`scripts/review_image_cases.py` mutates a long directory index, makes regular-file storage partially overlap, and changes the LZ4 option version. Baseline 0.2 accepted all three. Current result:

```json
{"invalid_images":3,"unexpectedly_accepted":[]}
```

These are explicit reproductions, not a count of all possible malformed inputs. The new data-extent validation allows identical shared blocks and rejects partial overlap/inconsistent descriptors. Compression-option validation covers record lengths and LZ4 version/flags, not every semantic parameter of every external compressor.

## Scale and memory

`scripts/scale_oracle.py` creates 2400 small configurations, a compressible log, 8 MiB seeded random data, one hardlink and one symlink, plus a user xattr. There are 2429 paths, 2428 unique inodes, 2402 unique regular files and 2403 regular paths. The ordinary fixture uses an 88 MiB log; the larger run uses `MOONSQUASH_SCALE_MIB=192`.

Measurements use `/usr/bin/time`, one run per case on the same server. RSS is peak KiB, not an allocation trace. Times are indicative and are not a universal performance promise. Unique payload excludes the duplicate hardlink path.

| Case | Unique payload bytes | Build time | Build peak RSS | Image bytes |
|---|---:|---:|---:|---:|
| Pre-streaming implementation, compressed metadata | 101793096 | 1.49 s | 438124 KiB | 8760141 |
| Final streaming implementation, compressed metadata | 101793096 | 0.90 s | 150076 KiB | 8760182 |
| Final streaming implementation, larger input | 210845000 | 1.32 s | 159348 KiB | 9134951 |

Thus the ordinary fixture's build peak decreased from about 428 MiB to 147 MiB. The larger fixture contains about 201 MiB of unique regular data, exceeding the old 128 MiB CLI limit, and builds at about 156 MiB peak RSS. Metadata remains in memory; this is not constant memory for unlimited inode counts.

| Final run | Ordinary fixture | Larger fixture |
|---|---:|---:|
| Verify time / RSS KiB | 2.64 s / 152740 | 5.20 s / 153552 |
| Raw-metadata build time / RSS KiB | 0.83 s / 152024 | 1.24 s / 155068 |
| Raw versus compressed metadata semantic diff time / RSS KiB | 8.95 s / 161264 | 18.55 s / 165476 |
| Raw-metadata image bytes | 8965462 | 9343504 |
| Official build time / RSS KiB | 0.49 s / 119268 | 0.86 s / 208764 |
| Verify official image time / RSS KiB | 2.66 s / 149288 | 5.19 s / 152284 |
| Official extract MoonSquash image time / RSS KiB | 0.08 s / 109060 | 0.11 s / 218820 |

Both final runs passed all 2403 per-path content comparisons using streaming SHA-256, hardlink identity and xattr checks. Repeated MoonSquash builds are byte-identical. Semantic diff is empty both between raw/compressed metadata variants and between official/MoonSquash images. The official timings involve different process structures and are reference observations, not an equivalent-settings benchmark claim.

## Actual public distribution image

`scripts/distribution_oracle.py` tests [OpenWrt 24.10.0 x86-64 squashfs rootfs](https://downloads.openwrt.org/releases/24.10.0/targets/x86/64/openwrt-24.10.0-x86-64-generic-squashfs-rootfs.img.gz). The downloaded gzip SHA-256 matches the [published checksum list](https://downloads.openwrt.org/releases/24.10.0/targets/x86/64/sha256sums): `363a441352bc69540bf34e862d291bda3d574214621c440ba0fb9a478ab3459e`. This is checksum matching over HTTPS, not a claim of verifying the release's cryptographic signature.

The XZ image has 1564 inodes/paths, 1225 regular files, 224 symlinks, 114 directories including root, one character-device record, 47 fragments and an export table. MoonSquash verified 21798569 regular-data bytes. All 1225 extracted file contents were compared by streaming SHA-256 against official extraction, along with 224 symlink targets and 113 non-root directories. `/dev/console` was compared as a character-device listing and checked in MoonSquash's omission report; the official extraction explicitly excludes it and MoonSquash never creates it. Ownership omissions are reported. The contents were not installed, mounted or executed, and the downloaded artifact is excluded from Git/package.

This adds one real publicly distributed filesystem image, not a broad firmware compatibility claim. Download/reproduction commands are in README and the prepared CI includes this pinned case.

## Reproduction and limitations

Run the commands in README after `moon build --target js`. For the larger case:

```sh
MOONSQUASH_SCALE_MIB=192 python3 scripts/scale_oracle.py scripts/moonsquash.cjs scripts/host.py
```

The CLI/build_to default cumulative budget is 4 GiB; individual files and physical image offsets remain below 2 GiB. These limits were not all pushed to their exact maximum in tests. `build_image` intentionally retains its 128 MiB convenience limit. Stable sources are required; concurrent same-size modification is not a snapshot operation.

Only the public OpenWrt image was used for real distribution validation; existing protected system images were left untouched. There is no public CI execution, registry installation, kernel mount certification or exhaustive fuzz result. See [strict review](../strict-review.md) for remaining submission risks.
