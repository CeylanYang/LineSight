# Current development — local release 1.1.10

Active release source: `C:/Users/29668/LineSight-workspaces/bilingual`.
Latest completed local release: **1.1.10+12**, at
`C:/Users/29668/LineSight-releases/1.1.10/`. Previous releases are preserved.
This source derives from the accepted 1.1.9 source archive. The asynchronous
search experiment remains paused in the separate startup-performance workspace.
D: remains full with the original 1.1.6 source. Do not retry the rejected cache
deletion. No commits or external publication occurred.

## Completed language release

- **我的 / Profile → 语言 / Language** is a clickable row below the account
  card. Its dialog switches between 中文 and English, updates the interface
  immediately and saves the device preference in SQLite. The sign-in page also
  has a language selector. Chinese is the default.
- The 934-message catalog covers navigation, forms, validation, statistics,
  help, backup/restore and progress. User content retains its original text;
  review drafts and sign-in inputs survive language changes. English defect
  searches and export-preview language snapshots preserve stored identifiers.
- **84 host tests passed**; analysis found no issues. The catalog audit found
  no missing static UI keys. English layout coverage includes 14 pages at
  320/1100 px with 1.5× text.
- The Android language journey passed with a separate real SQLite database:
  actual Profile row clicks in both directions, reopened language preferences,
  concurrent appearance/language writes, retained review drafts and submitted
  multilingual notes. Five screenshots are retained. The application package
  was kept installed throughout the journey.
- Normal-entrypoint ARM64/x64 release builds passed. Packages are version
  1.1.10, codes 2012/4012, API 24+, target 36, without Internet permission or
  a debuggable flag. APK v2 signatures match the 1.1.9 certificate.
- The emulator has the x64 release installed and open. Pulled installed APK
  bytes match the release hash. UID 10306 and firstInstallTime were retained;
  the device timezone is GMT. The launch reported 12,911 ms to Displayed,
  which is not a measurement of when the page becomes usable. Startup latency
  remains unresolved. The final release sign-in screenshot was visually checked.

See [1.1.10 changes](CHANGELOG_1.1.10.md) and [language acceptance steps](LANGUAGES.md).
Release reports retain the host/Android logs, APK metadata, installed-byte
verification and screenshots, including earlier failed attempts.

## Retained 1.1.9 checkpoint

Review forms protect in-memory drafts, validate notes inline and check whole
record evidence atomically before submission. Changed records preserve drafts
and require explicit re-review; clean forms refresh. Locking clears the route.
The preview legend wraps at narrow widths and large text sizes.

Record pages cache one complete query result and ID set; selection, pagination
and unrelated theme changes reuse it. Cache invalidation retains local-day/DST
semantics. ThemeData is reused. Startup tracing remains opt-in and is off in the
normal APK. Startup visuals and renderer remain unchanged.

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

## Retained follow-up work

The search experiment is paused. Future work can continue secondary-page accessibility and observe typing/search with large
record sets on Android before choosing asynchronous search or indexing. Any
pending-result design must keep selection and export scope consistent.
Whole-workspace clone/validation/serialization cost remains. First post-install
startup latency is unresolved; display wait completion is not a usable-page
timing. Do not restore the withdrawn blur experiment or switch renderers based
only on earlier noisy emulator measurements.

## Evidence and retained investigations

- [1.1.9 changes](CHANGELOG_1.1.9.md) · [local validation and package hashes](LOCAL_WORKSPACE.md).
- [Review draft behavior](RECORD_REVIEW.md) · [query semantics and desktop measurements](RECORD_SEARCH_PERFORMANCE.md).
- [Startup investigation](LAUNCH_INVESTIGATION.md) · [storage tradeoffs](STORAGE_PERFORMANCE.md).
- Startup, query and review development archives remain under
  `C:/Users/29668/LineSight-investigations/`, each with its original source,
  success/failure evidence and device-state notes.
- Prior driver cleanup reset emulator package data (UID 10301 → 10306). This
  release used `--keep-app-running`; UID and firstInstallTime remained unchanged.
  Follow [the device procedure](ANDROID_VERIFICATION.md) for future runs.

The Chinese/English release is complete; startup/search investigations remain separate.
