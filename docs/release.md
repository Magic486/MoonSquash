# Local release candidate 0.3.0

2026-11-05. The user selected GitHub/Mooncakes account `Magic486`. Repository: https://github.com/Magic486/MoonSquash; module: `Magic486/moonsquash@0.3.0`. The original local development history is preserved with its original authors and dates. Publication checks and registry installation results will be recorded below. Contest registration and acceptance remain separate.

Build with the documented toolchain, run JS/Wasm-GC tests, and run the complete Linux oracle/regression commands in README, including the malformed-image, strict-specification and scale checks. Version 0.3 adds compressed metadata and streaming construction; the archive consumer exercises both memory and streaming APIs. `moon package` produces `_build/publish/Magic486-moonsquash-0.3.0.zip`. `scripts/package_consumer.py` extracts that actual archive into an independent workspace and runs a separate consumer on both library backends.

The archive includes required adapters, source, tests, example, LICENSE and documentation. It excludes `.local`, `_build`, `.git`, tool caches, CI/hooks and `output/` (PDF). Git includes only reviewed source/materials; no private host addresses, keys, captures or raw third-party downloads belong in the distribution. The manifest points to the selected public repository.

Publication checklist: push the actual history, verify CI on the final source commit, publish with the verified Magic486 Mooncakes login, and install the exact registry version in a separate workspace. Pending checks are not claimed as complete.

Evidence: `docs/test-evidence/review-0.3.md`. Compatibility/operational limits: README. Earlier `milestone-1.md` is historical and must not be rewritten to claim the newer functionality existed earlier.
