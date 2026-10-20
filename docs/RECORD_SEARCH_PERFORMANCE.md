# Record query reuse — development after 1.1.8

Date: 2026-10-14. Included in local release **1.1.9+11**. Both Android query
scenarios were rerun successfully on the versioned source with New York DST
boundaries. The measurements and development-checkpoint logs below are historical;
release qualification is recorded in [the 1.1.9 changelog](CHANGELOG_1.1.9.md).

## Behavior and invalidation

`RecordQueryCache` keeps one filtered/sorted result and its complete ID set per
record page. Pagination, checkbox changes and unrelated preference/theme
notifications reuse that result. It does not retain lowercase copies of notes
or a history of queries. The retained collections are O(matching records).

The cache checks workspace identity, inspection-list identity and length,
workspace revision, session, lowercase query, archive/status/station filters,
sort direction and resolved date-boundary instants. Production commits replace
the workspace and advance revision. Initialization can replace a workspace
without changing revision. Code that edits existing records or reorders/replaces
items in the same list must advance revision; publicly mutable model fields do
not independently emit invalidation events.

Date boundaries are resolved once on each request using `localDay(firstDate)`
and `localDay(lastDate, 1)`. Results use the same inclusive-start,
exclusive-next-day rule. Keys contain epoch microseconds, so a subsequent build
after a device timezone change cannot match obsolete resolved boundaries. The
cache does not add its own timezone-change listener.

Search still lowercases the exact joined sequence of serial, ID, defect, recipe,
note and operator, separated by spaces. Queries are not trimmed: whitespace,
newlines and matches across fields retain their meanings. Empty queries skip
search text assembly. Verdict filters and timestamp sorting retain their old
comparators, including equal timestamps.

The list and ID set are unmodifiable; inspection objects remain workspace
references. CSV continues to call `captureCsv` for an independent snapshot of
**all matching records in the displayed sort order**. Selection likewise covers
all results, including rows beyond the first 30. After a data/filter change,
selection is intersected with the new result IDs.

## Verification

- All **64 host tests** passed. A subsequent analyzer run after removing a
  redundant import reported **No issues found**.
- A compatibility oracle retains the old algorithm and checks **960 filter
  combinations**, including whitespace, mixed case, multiline/Unicode notes,
  cross-field queries, verdicts, archive/station/date filters, both sort
  directions and tied timestamps.
- Independent invalidation tests cover workspace/list identity, list length,
  revision and session. Tests also check immutable collections, a single retained
  result, in-place edits with revision changes and local-day boundaries.
- A widget fixture contains 65 records with long notes. Each eligible note is
  read once when searching. Selection, deselection, pagination and a dark-theme
  update cause **zero additional note reads**. The export still includes all 65
  results in order, despite a 60-row page limit and only 64 selected rows.
- Widget replacement tests check archive/note changes, removed selections and
  restoring a new workspace without advancing revision. Existing four-entry CSV
  scope tests also pass.
- **2 Android scenarios passed**: real SQLite review, archive/unarchive,
  restore/undo, simulation, preferences and session changes refresh/reuse the
  expected results; New York 23/25-hour days include the start instant and exclude
  the following midnight. The runner completed `+2` scenarios and teardown.
  The original GMT timezone was restored in `finally` and checked afterward.

Logs: `build/record-query/host-tests-final.log`, `analyze-final.log`,
`focused-tests-final.log`, and `android-query-journey.log`.
The Android runner's first debug install was rejected because version code 10
was below the installed release split code 4010; Flutter then uninstalled the
release app and installed the test package on the disposable emulator. This
replacement resets that emulator package's data. The initial installation failure
is preserved; the two subsequently executed test scenarios passed. Historical
host APK/source/evidence files were preserved.
The two earlier focused runs failed because their
test finders assumed lazy list children stayed mounted; those logs are retained.
The UI implementation was not changed to accommodate these test assumptions.

## Desktop query microbenchmark

`tool/benchmark_record_query.dart`, Dart 3.12.2 JIT on Windows 11, 4,000 records,
2,000-character notes, 15 warmups and 60 samples per path/case. The original path
includes filtering, sorting and the ID set. The new path includes those operations
on a miss, plus unmodifiable result collections. Sample order alternates;
membership and exact order are checked outside each timed interval.

Median query time, in milliseconds:

| Query | Matching rows | Original | Cache hit | Revision changed |
|---|---:|---:|---:|---:|
| Empty | 2,666 | 0.683 | 0.0030 | 0.7545 |
| `质` | 2,666 | 85.799 | 0.0055 | 84.1795 |
| `NO-MATCH` | 0 | 108.050 | 0.0065 | 107.7520 |
| `CSV-000001 csv-1` | 1 | 118.9475 | 0.0075 | 115.5110 |

Raw samples are summarized with min/max/p95 in
`build/record-query/desktop-benchmark-final.json`. This is one desktop run, not
Android UI latency or a frame-rate measurement. New queries and data changes
still scan synchronously; there is no demonstrated general miss-path speedup.
The empty-query miss has modest extra collection overhead. Widgets and selected
ID pruning still rebuild on a cache hit. Heap usage is not measured; fixture
notes share a string. A preliminary benchmark omitted the original ID-set step
and is retained separately; the table uses the final comparison only.

## Remaining work

Observe typing with large record sets on devices before introducing asynchronous
search or indexing. Such changes need an explicit consistency rule for pending
results, selection and export. Whole-workspace transaction cost and first-install
launch delay remain unresolved by this change.

## Retained checkpoint and emulator state

Exact source ZIP, changed-source overlay, hashes and reports:
`C:/Users/29668/LineSight-investigations/record-query-20261014/`.

After testing, the installed x64 APK was read back and its SHA-256 matched
accepted 1.1.8 (`694c1f19e0f13a35f4b21c3ad050a6d0dcc30eb5c8bea26466d76ce42bd53c0b`).
The normal default Impeller/OpenGLES backend was observed, with no diagnostic
startup events. Both screenshots show the complete 1.1.8 administrator setup.

The first post-install wait timed out (wait 15,620 ms; Android Displayed later at
15,935 ms). The next cold launch passed (Displayed/TotalTime 6,981 ms). These are
observations of the **accepted 1.1.8 binary**, not measurements of the new query
code. The first failed wait remains a failure. The original startup blur files
and startup-layout test still match accepted 1.1.8 byte for byte.
