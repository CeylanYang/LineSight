# Storage investigation — 1.1.8 development

## Method and retained experiments

The fixture contains 4,000 inspections with long Unicode notes: 25,264,407 UTF-8 bytes. `storage_compare_test.dart` runs four baseline/candidate pairs in one Android emulator process, alternating order each round. Baseline storage is the frozen 1.1.7 implementation in `test_support/baseline_state_storage.dart`. Both versions write the same key within a caller-owned SQLite transaction and read back the entire exact string.

`prepare-baseline` and `prepare-worker` measure the same pure preparation function on the main isolate and in `compute`, respectively. Baseline production storage hashes incrementally between individual SQLite inserts; it does **not** call the synchronous preparation function. Preparation gaps therefore must not be presented as baseline production write gaps.

The measurements use Flutter profile mode (AOT) on disposable Android emulator `emulator-5554`. A 16 ms timer reports main-isolate scheduling gaps, not rendered frame times. Fixture generation and equality assertions are outside each timed phase. Caches are not flushed; first runs, GC and host scheduling can affect this small sample. All four runs are retained in the summaries. No physical-device speed or capacity guarantee follows.

`tool/summarize_storage.py LOG... --output REPORT.json` retains individual samples and calculates medians. It also lists runs 2–4 separately for transparency without replacing the four-run results.

## Initial worker experiment

The first implementation retained all split chunk strings in the prepared write plan. The AOT results in `build/storage-compare-profile-1.1.8.log` were:

| Phase | Baseline median | Candidate median | Baseline longest-gap median | Candidate longest-gap median |
|---|---:|---:|---:|---:|
| Pure preparation | 679 ms | 1,138 ms | 679 ms | 29 ms |
| Transactional write | 2,898 ms | 2,650 ms | 60 ms | 70 ms |
| Transactional read | 1,507 ms | 1,845 ms | 152 ms | 51 ms |

The first candidate write took 4,485 ms with a 1,038 ms gap. This outlier is retained; its cause is not established. Earlier separate debug runs were slower overall with workers, including actual archive transactions (medians 3,288 → 4,594 ms). Debug and AOT results are not interchangeable. Logs: `storage-baseline-1.1.8.log`, `storage-worker-1.1.8.log`.

## Offset preparation

The current plan retains an immutable list of chunk end offsets and the manifest. Hashing uses one temporary bounded chunk at a time. The main isolate creates substrings for only the current batch of eight inserts. This avoids retaining a second complete set of chunk strings in the write plan; overall app/native memory has not been measured.

The first offset AOT run overlapped briefly with host static analysis. Its raw evidence is preserved as `build/storage-offsets-profile-1.1.8.log`; a separate run reused the already-built APK after host tests and analysis had finished (`storage-offsets-quiet-profile-1.1.8.log`). Both passed exact-data checks. The separate run completed in 43 seconds:

| Phase | Baseline median | Offset candidate median | Baseline longest-gap median | Candidate longest-gap median |
|---|---:|---:|---:|---:|
| Pure preparation | 687 ms | 1,051 ms | 687 ms | 26 ms |
| Transactional write | 2,609 ms | 2,439 ms | 61 ms | 79 ms |
| Transactional read | 1,486 ms | 1,743 ms | 154 ms | 47 ms |

This sample shows a 6.5% shorter write time but a longer write scheduling gap, and a 17.3% longer read with a 69.8% shorter scheduling gap. This is a responsiveness/latency tradeoff, not a general speed improvement. Runtime frame performance, memory peaks and physical devices have not been measured. `build/storage-comparison-1.1.8.json` retains all three AOT comparisons and all individual samples.

## Actual archive operations

`storage_profile_test.dart` was run in two separate AOT processes, first with the frozen 1.1.7 storage and then with the offset candidate. Only `lib/state_storage.dart` was temporarily substituted; the runner restored the candidate's exact bytes in `finally`, and the SHA-256 was checked again afterward. Each process registers/logs in a local administrator, performs three storage rounds, then archives/unarchives a real record three times through `AppStore.archive`. It checks revision increments, preserved original verdict, changed archive state and full persisted-model equality after each operation.

| Phase | Baseline median | Offset candidate median | Baseline longest-gap median | Candidate longest-gap median |
|---|---:|---:|---:|---:|
| JSON encoding | 110 ms | 135 ms | 110 ms | 135 ms |
| Transactional write | 2,398 ms | 2,670 ms | 60 ms | 101 ms |
| Transactional read | 1,496 ms | 1,912 ms | 151 ms | 49 ms |
| Actual archive | 2,480 ms | 2,601 ms | 89 ms | 94 ms |

Both complete scenarios passed. The observed real-archive median increased by 4.9% (121 ms). The separate runs do not isolate host/process variation; even unchanged JSON encoding differed. These results support reduced read scheduling gaps, but **do not establish faster writes or business operations**. Logs and all individual samples: `archive-baseline-profile-1.1.8.log`, `archive-offsets-profile-1.1.8.log`, `archive-comparison-1.1.8.json`. Source restoration proof: `archive-profile-source-proof-1.1.8.json`.

The offset candidate is retained for reduced read scheduling stalls and bounded write-plan retention, with the measured latency costs disclosed. The independent records-page improvement avoids needless long-note scans on empty queries; its test checks note-access counts and unchanged search results. Whole-workspace serialization remains a separate optimization target.

## Compatibility and remaining costs

SQLite schema stays 3; chunk manifest format stays 2. Large writes still use the caller's transaction. Chunks are committed in groups of eight, with old-chunk deletion in the first batch and the manifest in the last. This requires rollback across batches, including related state and account changes, on failure.

Legacy oversized single-cell values still use SQLite `substr` reads. Hash/count/order/length validation precedes returning chunked values. Workers add startup/transfer costs and can lengthen total read latency even when scheduling gaps decrease. The full working model, assembled read string and whole-workspace clone/JSON conversion remain memory and latency costs. AppStore still clones, validates and serializes business changes synchronously.
