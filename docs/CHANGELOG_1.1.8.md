# 1.1.8 — storage scheduling and records filtering

Completed local checkpoint: 1.1.8+10. Packages and exact source: `C:/Users/29668/LineSight-releases/1.1.8/`.

## Changes

- Large-state hashing and read assembly run in workers. Write preparation retains chunk offsets, and SQLite receives batches of up to eight chunks inside the existing business transaction.
- Manifest validation rejects malformed counts, lengths and hashes before requesting chunks. Existing version-2 chunks and oversized legacy cells remain readable.
- Empty record searches skip constructing/lowercasing long-note search strings. Station, archive, date and verdict filters exclude records before search text is constructed. Nonempty case-insensitive and cross-field matching remain unchanged.

## Compatibility

SQLite schema 3, LSB 2, JSON 1 and existing CSV formats are unchanged. A failed batch must roll back the entire caller transaction, including the old chunks, manifest and associated changes. Credentials, roles, audit attribution and session behavior retain their existing implementation.

## Measurement boundary

The four-pair AOT emulator comparison showed shorter read scheduling gaps with longer total reads, and slightly shorter writes with longer write gaps. See [raw observations, method and limits](STORAGE_PERFORMANCE.md). This release must not be described as universally faster. Whole-workspace cloning, validation and JSON encoding remain synchronous; physical-device performance and peak memory are unmeasured.

## Verification

- **56 host tests passed**; static analysis found no issues.
- **7 Android core scenarios passed**: forced second-batch rollback with byte-exact old chunks/manifest and related state; corruption detection and bidirectional 1.1.7 compatibility; startup validation; restore/undo and export attribution; local authentication/roles; both recovery scenarios; large legacy-state upgrade, restoration and reopening.
- **2 timezone scenarios passed** in America/New_York, including 23/25-hour days, forced migration rollback, original preservation and legacy restore choice. GMT was restored in `finally`.
- Three alternating AOT comparison scenarios passed exact string checks. Both separate AOT real-archive profiles passed full persisted-model equality, revision, archive-state and original-verdict checks. The temporary baseline source was restored byte-exactly and its SHA-256 checked.

Normal-entrypoint ARM64/x64 release builds, manifest checks, x64 installation and three cold launches passed. [Package hashes and complete evidence](LOCAL_WORKSPACE.md).

## First-install launch observation — 1.1.8

The first post-install `am start -W` reported `Status: timeout`, `LaunchState: UNKNOWN`, with `WaitTime: 18,136 ms`. The app process remained alive, the inspected crash buffer was empty, and the after-timeout screenshot showed the complete administrator-setup page with version 1.1.8. Its cause remains unknown. Three subsequent force-stop/cold-start checks passed. The original timeout log, process/crash logs and image are preserved in reports; the failed wait is not counted as a pass. A similar first-install delay was observed in 1.1.7 and remains a follow-up investigation.
