# LineSight 1.1.6 — streamed CSV and export previews

## Confirm the exact selection

All four CSV entry points now open a confirmation page: all records from Data Management, filtered records, one record's detail, and the current statistics range. The page shows the scope and filters/order, total and archived counts, example/simulation count, snapshot time, column descriptions and up to three preview records.

The selection becomes an immutable scalar snapshot when this page opens. It freezes every exported value, station name and row order. Changes made afterward, including reviews, archiving and station renaming, cannot silently alter this preview. Return and reopen the page to export the latest state. All-record exports include archived records; filtered/statistics exports preserve the caller's exact selection and order. An empty all-record selection can produce a header-only CSV.

## Generate and save large files

CSV serialization and file I/O run in a worker isolate. Rows are encoded incrementally, buffered in approximately 64 KiB batches and written to an app-private temporary file. The app no longer constructs a full CSV string and byte array for production exports. Generation reports progress and can be cancelled; leaving the page cancels preparation. Failed, cancelled and completion-time-cancelled preparations remove their temporary output.

After generation, Android's document picker saves with the `text/csv` MIME type. The existing native streaming copy reads back the destination and verifies its size and SHA-256 before reporting success. Cancelling the picker remains a cancellation. Failed verification is reported as an unconfirmed save; users can inspect the chosen destination. CSV uses the existing 256 MiB maximum file size and a 16 MiB per-row guard; exceeding a limit fails explicitly without truncating records. Narrow the selection to export less data.

The active workspace and immutable scalar snapshot still reside in memory; isolate transfer and the existing transactional audit writes also consume memory and time. The file limit is not a measured capacity guarantee for every device. Pre-time-upgrade original JSON exports retain the prior 20 MiB path.

## Format and traceability

The existing 15 columns, UTF-8 BOM, CRLF row boundaries, quoting and UTC timestamps remain. Embedded commas, quotes, line breaks and Unicode stay within their original cells. Original inspection verdicts and review results remain separate. Formula-like text is prefixed with an apostrophe; protection now also covers leading whitespace before `=`, `+`, `-` or `@`. This protection may make the apostrophe visible in some spreadsheet readers.

CSV is an unencrypted analysis export. It does not contain recipe parameters, complete operation history or local accounts and cannot replace an LSB/JSON business backup. The `配方快照` column contains the recipe snapshot name, matching earlier CSV versions.

Export authorization remains restricted to engineers and administrators. The captured session is checked before generation and before opening native saving. A save already opened by an authorized actor can finish after automatic locking; its one-use ticket records the initiating actor. Completion records the exact selection as audit targets, scope/snapshot time, verified byte count and SHA-256. CSV success, cancellation and failure never replace the last successful business-backup receipt. Verification metadata is required before the store accepts CSV success.

The audit detail page presents CSV byte counts and hashes in a dedicated **文件校验** section. Other before/after changes remain visible. Shared detail rows now leave an explicit 12-pixel gap between their labels and values so long labels do not touch the adjacent value.

SQLite remains schema 3; business backup formats remain LSB 2 and JSON 1. Earlier versioned packages are retained.

## Validation status

All 42 host tests passed: immutable snapshots, CSV fields/escaping, output over 20 MiB, cancellation/limits, empty selections, four entry routes, audit metadata and narrow/large-text/dark-tablet layouts. Static analysis reported no issues. Four Android authentication/data-management/recovery regressions passed, as did the final actual CSV save/open/cancel/lock journey. Python's independent CSV parser verified all 4,000 rows and 15 fields of the 24,611,792-byte native file. Native LSB regression and x64 release installation/cold launch passed. Packages and reports: `C:/Users/29668/LineSight-releases/1.1.6/`; see `LOCAL_WORKSPACE.md`.
