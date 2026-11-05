# Release 0.3.0

2026-11-05. The user selected GitHub/Mooncakes account `Magic486`. Repository: https://github.com/Magic486/MoonSquash; module: `Magic486/moonsquash@0.3.0`. The original local development history is preserved with its original authors and dates. Publication checks and registry installation results will be recorded below. Contest registration and acceptance remain separate.

Build with the documented toolchain, run JS/Wasm-GC tests, and run the complete Linux oracle/regression commands in README, including the malformed-image, strict-specification and scale checks. Version 0.3 adds compressed metadata and streaming construction; the archive consumer exercises both memory and streaming APIs. `moon package` produces `_build/publish/Magic486-moonsquash-0.3.0.zip`. `scripts/package_consumer.py` extracts that actual archive into an independent workspace and runs a separate consumer on both library backends.

The archive includes required adapters, source, tests, example, LICENSE and documentation. It excludes `.local`, `_build`, `.git`, tool caches, CI/hooks and `output/` (PDF). Git includes only reviewed source/materials; no private host addresses, keys, captures or raw third-party downloads belong in the distribution. The manifest points to the selected public repository.

Publication checklist: push the actual history, verify CI on the final source commit, publish with the verified Magic486 Mooncakes login, and install the exact registry version in a separate workspace. Pending checks are not claimed as complete.

Evidence: `docs/test-evidence/review-0.3.md`. Compatibility/operational limits: README. Earlier `milestone-1.md` is historical and must not be rewritten to claim the newer functionality existed earlier.

## Published results

- GitHub: https://github.com/Magic486/MoonSquash (public, default branch `master`). Original local commit SHAs, authors, dates and parents were preserved. The first public source freeze is `42b409036db2e380c2581cc045a2b7860d749622`.
- Mooncakes: https://mooncakes.io/docs/Magic486/moonsquash@0.3.0 . The CLI credential username was checked as `Magic486` immediately before publication; server response was `200 OK`. The actual archive contains 62 files and excludes local/private directories and the PDF.
- Registry consumer: a separate workspace containing only the consumer installed `Magic486/moonsquash@0.3.0` from the registry. `moon tree` confirms the exact dependency; representative memory-build, streaming-build, range, xattr, hardlink, verify and diff APIs passed on JS and Wasm-GC. This is separate from archive/workspace consumption.
- Release: https://github.com/Magic486/MoonSquash/releases/tag/v0.3.0 . Later distribution fixes in `master` correct README's Git symlink mode; the published package already contains README as a regular file. Newer formatter migration differences are reported with `moon fmt --warn`, while compilation and all functional checks remain required. September-toolchain strict formatting was checked locally.
- Public CI: https://github.com/Magic486/MoonSquash/actions/workflows/validate.yml . Check the run's exact commit SHA; initial failures are retained as evidence rather than concealed.

The package is immutable. Subsequent Git-only file-mode, workflow and publication-record commits do not rewrite the published ZIP or its source-freeze tag. No contest form was submitted and no official acceptance is claimed.
