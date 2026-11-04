# Development status

2026-11-05: M1-M4 implemented for the documented 0.3 profile, superseding the initial read/write milestone.

- Reader: all inode types, six codec adapters, fragments/sparse data, inline/out-of-line xattrs, owner IDs, export indexes and random-access input.
- Builder: compressed data and metadata, streaming source/sink API, tail packing, metadata/ownership, hard links, special records, xattr/export tables and exclusive publication.
- Workflow: directory packing, safe extraction with omission reporting, semantic diff and structural verification.
- Delivery: API/demo, independent six-codec Linux oracle, 21 JS/Wasm-GC tests, archive consumer, 201 MiB scale checks and local submission materials. Evidence is in `test-evidence/review-0.3.md`; findings and remaining contest risks are in `strict-review.md`.

Intentional limits are in README. No remote publication, registry install, registration or official acceptance is claimed. `local/moonsquash` is a placeholder namespace.
