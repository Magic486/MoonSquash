# Development status

2026-11-05: M1-M4 implemented for the documented 0.2 profile, superseding the initial read/write milestone.

- Reader: all inode types, six codec adapters, fragments/sparse data, inline/out-of-line xattrs, owner IDs, export indexes and random-access input.
- Builder: compressed data, tail packing, metadata/ownership, hard links, special records, xattr/export tables and exclusive publication.
- Workflow: directory packing, safe extraction with omission reporting, semantic diff and structural verification.
- Delivery: API/demo, independent Linux oracle, JS/Wasm-GC tests, archive consumer and local submission materials. Evidence is in `test-evidence/release-0.2.md`.

Intentional limits are in README. No remote publication, registry install, registration or official acceptance is claimed. `local/moonsquash` is a placeholder namespace.
