# Local release candidate 0.3.0

2026-11-05. Source, tests, CLI adapters, API, example and submission drafts are local. `local/moonsquash` is a placeholder; no public owner, remote, registry version or registration has been selected or created.

Build with the documented toolchain, run JS/Wasm-GC tests, and run the complete Linux oracle/regression commands in README, including the malformed-image, strict-specification and scale checks. Version 0.3 adds compressed metadata and streaming construction; the archive consumer exercises both memory and streaming APIs. `moon package` produces `_build/publish/local-moonsquash-0.3.0.zip`. `scripts/package_consumer.py` extracts that actual archive into an independent workspace and runs a separate consumer on both library backends.

The archive includes required adapters, source, tests, example, LICENSE and documentation. It excludes `.local`, `_build`, `.git`, tool caches, CI/hooks and `output/` (PDF). Git includes only reviewed source/materials; no private host addresses, keys, captures or raw third-party downloads belong in the distribution. The `repository` packaging warning is expected until a real publication target is chosen; no placeholder URL is fabricated.

The prepared GitHub workflow is not evidence of an executed public CI run. Publication work remains: choose identity/repository/namespace, update metadata/links, publish the actual history, run remote CI, publish one immutable package version, and verify a registry consumer. None of these is silently substituted by local packaging.

Evidence: `docs/test-evidence/review-0.3.md`. Compatibility/operational limits: README. Earlier `milestone-1.md` is historical and must not be rewritten to claim the newer functionality existed earlier.
