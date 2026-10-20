# LineSight 1.1.9 — review drafts and repeated-query reuse

Completed local checkpoint: **1.1.9+11**. Packages, exact source, full patch from 1.1.8 and reports: `C:/Users/29668/LineSight-releases/1.1.9/`.

## Review details

- Unsaved review notes and verdict changes show their status and require a
  discard decision when leaving. Notes use the existing 3–2000 character limits
  with inline feedback. Saving blocks edits, back navigation and duplicate
  submissions.
- Clean forms follow the current record. If a record changes while a draft is
  open, the form preserves the draft and requires reloading or explicit review
  of the latest evidence before submission. Confirmation checks the evidence
  again; the atomic database commit also checks the original snapshot.
- Stale submissions do not write data or audit entries. Changes to unrelated
  records do not invalidate this record's evidence. Original inspection results
  remain immutable.
- Removed or archived records keep draft text available for copying. Locking
  clears the route and its in-memory draft. Drafts do not survive process exit.
- Synthetic preview legends wrap on narrow screens with large text, including
  the 320 px / 1.8× text configuration that previously overflowed.

[Detailed behavior and evidence](RECORD_REVIEW.md).

## Repeated work

Record pages retain one filtered/sorted result and its full ID set. Pagination,
selection and unrelated theme updates can reuse it. Data, session, filter, sort
and resolved local-day boundaries invalidate the result. Search retains exact
joined-text semantics, including whitespace and matches spanning fields. Bulk
selection and CSV scope still cover all matches beyond the visible page.

Light/dark themes are reused across store notifications. Startup phase/frame
diagnostics are available through `LINESIGHT_STARTUP_TRACE`, disabled in normal
release builds. Startup visuals and the production renderer are unchanged.

[Query checks and desktop measurements](RECORD_SEARCH_PERFORMANCE.md) ·
[Startup observations](LAUNCH_INVESTIGATION.md).

## Compatibility and limits

SQLite schema 3, storage format 2 and backup/export formats remain unchanged.
Existing development signing is retained. No account/cloud service is added.

New queries still scan synchronously. Desktop cache-hit timings are not Android
frame measurements. Whole-workspace copying, validation and serialization still
have costs. The first post-install launch delay is unresolved; a timed-out wait
remains a failure even when the page eventually appears. Native CSV/LSB picker
journeys retain their 1.1.6 evidence and are not rerun for this checkpoint.

## Qualification

- **76 host tests passed**; static analysis found no issues.
- **7 Android core scenarios passed**: chunk rollback/corruption/compatibility,
  startup validation, restore/undo/export attribution, local accounts and roles,
  both authenticated recovery scenarios, and large backup/SQLite reopening.
- **4 Android time/query scenarios passed** in America/New_York: both time
  portability cases, committed query invalidation/session changes and 23/25-hour
  local-day filtering. GMT was restored and verified.
- **2 Android review scenarios passed**: real SQLite stale-evidence rejection,
  unchanged failed writes/audits/revision and reopening; visible Chinese draft,
  validation, leave confirmation, conflict acknowledgement, save and lock flow.
  Five final review screenshots were visually checked.
- Each suite used a prebuilt debug APK with code 4011 and
  `flutter drive --keep-app-running`. Package UID remained **10306**, and
  firstInstallTime stayed unchanged through tests and release installation
  after normalizing each recorded device timezone to UTC.
  This is package-retention evidence, not a byte-for-byte audit of all databases.
- Normal-entrypoint ARM64/x64 release builds passed. Manifests show API 24+,
  target 36, codes 2011/4011, no Internet permission and no debuggable flag.
  APK v2 signatures match the existing development certificate. Installed x64
  bytes match the packaged APK; default Impeller/OpenGLES was observed and
  startup diagnostic events were absent.
- 3 cold-start waits passed; 1 failed. The first post-install wait reported timeout at 20,046 ms. All captured release pages were visually checked. Failed waits remain failures even if a later frame appeared.

Native CSV/LSB picker journeys were not rerun; their latest evidence remains
1.1.6. Historical startup timeouts and earlier failed experiments remain archived.

The source ZIP and full patch are verified against all source bytes.
[Package hashes and complete evidence](LOCAL_WORKSPACE.md).
