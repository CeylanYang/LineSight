# LineSight local workspace — implementation record

Date: 2026-10-14. Current source version: 1.1.6+8. The Week 4 tracker is retained as historical project/team context; this record describes the implemented app. See [1.1.1 changes](CHANGELOG_1.1.1.md) for audit extensions, [1.1.2 changes](CHANGELOG_1.1.2.md) for restore previews, [1.1.3 changes](CHANGELOG_1.1.3.md) for timestamps, [1.1.4 changes](CHANGELOG_1.1.4.md) for complete backups, [1.1.5 changes](CHANGELOG_1.1.5.md) for authenticated startup recovery and [1.1.6 changes](CHANGELOG_1.1.6.md) for streamed CSV export.

## Product routes

| Entry | Secondary routes and actions |
|---|---|
| First launch / login | Create administrator, optional examples, recovery-code acknowledgement, password recovery |
| 工作台 | Alerts, station live view, simulated inspection, latest record, quality insights |
| 检测记录 | Text/date/station/verdict filters, sorting, selection, archive/restore, record detail, quality review, CSV |
| 配方中心 | Recipe detail, editor, copy, delete, changeover, changeover log, diagnostics, station editor |
| 我的 | Profile, password change, role matrix, members, member creation/permissions, audit log, data management, guide |
| 操作日志 | Action/time/text filters, event details, before/after changes, related record/station/recipe navigation, export operation results |
| 数据管理 | Complete CSV, LSB/JSON backup selection, preparation/save progress, file selection and integrity check, restore preview, restore undo, sample add/clear, time-storage explanation and upgrade originals |
| 备份与还原点预览 | File time/size, object change counts, searchable added/replaced/removed lists, field comparison, current-data backup, confirmation against the previewed revision |
| 本机数据恢复 | Retry, administrator password/recovery-code verification, native backup selection, integrity/time preview, preservation and recovery confirmation |
| 异常恢复记录 | Recovery metadata, retained-original size, recovery ID, verified LSR original export and cancellation |
| CSV 导出确认 | All/filtered/single/statistics selection, immutable values and ordering, counts and row preview, generation progress/cancellation, native save/readback, persisted checksum in audit detail |

## Persistence and security behavior

- Database: `linesight_local_v1.db` inside the application's private database directory. Schema v3 stores local accounts separately from the transactional business-workspace snapshot and preferences, retains checksum-validated chunks for large state values, and adds recovery-original tables. Existing v1/v2 data upgrades in place; older releases cannot open the upgraded database.
- Passwords and recovery codes: PBKDF2-HMAC-SHA256, 210,000 iterations, independent random salts, 256-bit output; derived off the UI thread. Passwords are 8–128 characters. No built-in password or shipped account.
- Five failed authentication attempts lock that account for 60 seconds. Failures and lock expiry persist in SQLite.
- First account is administrator; subsequent accounts require an administrator and begin as operators. The current administrator cannot disable or demote themself.
- Authorization is enforced in store operations and reflected in the UI. Cold starts never restore a signed-in session. Backgrounding for 30 seconds triggers a fresh login when automatic locking is enabled. Locking replaces the navigator so a previous detail route cannot remain accessible.
- Sign-out clears authentication even if saving its audit entry fails, so unavailable storage cannot keep a user signed in.
- If business state cannot open but accounts remain readable, an enabled administrator can verify their password or recovery code and recover from a validated backup. Recovery access is separate from normal login and always expires after 30 seconds away. Original state/chunks and replacement data commit together; failed recovery rolls back. Unreadable SQLite files/table structures retain retry/help and are not automatically repaired or reset.
- User accounts share this device's business workspace. This is not a separate data vault per user.
- SQLite transaction commits business changes and the corresponding audit entry together. The UI updates after successful persistence. Original inspection verdicts and recipe snapshots remain intact when reviewed or changed over.
- Backup parsing checks schema, required types, unique IDs, references, parameter ranges, and size limits. A restore keeps existing local accounts/preferences, merges audit history, and stores one pre-restore rollback snapshot in the same transaction. Undo consumes that snapshot.
- Sample clearing removes only records explicitly marked as examples/simulations. All currently generated inspections are simulations and are marked accordingly. Audit history remains.
- Native file export writes actual UTF-8 CSV, JSON, LSB or LSR bytes. CSV/LSB/LSR saves stream from an app-private temporary file and verify destination bytes by reading them back. CSV doubles quotes, quotes cells, uses a UTF-8 BOM, and neutralizes formula characters including those preceded by whitespace. Cancelling a picker is not reported as success.
- Android automatic OS backup is disabled. The SQLite file and exported business backups are not encrypted. Recovery codes cannot recover data lost through uninstalling or deleting the database.

## Visual and interaction design

Blue/green local-workspace theme, high-contrast verdicts, translucent blurred panels with a solid fallback, phone navigation bar and tablet rail, custom-drawn lens logo and synthetic bracket imagery, persistent dark/glass/haptic/motion/lock preferences, loading states, confirmations for destructive actions, and empty states. The source brand SVG is `design/linesight-mark.svg`; its geometry is reflected in the Flutter and Android icons.

## Validation evidence — 1.1.0 checkpoint

- Host tests: `test/workspace_test.dart` covers serialization, invalid backup rejection, original-versus-reviewed verdicts, role-gated exports and CSV escaping. `test/layout_test.dart` exercises navigation and secondary routes in light/dark phone layouts and onboarding at 320 px and tablet widths.
- Android store test: `integration_test/local_workflow_test.dart` uses real SQLite and covers account creation, wrong-password rejection, role enforcement, simulations, review/archive, recipe changes, backups and undo, password changes/recovery, reopening the database, saved preferences and throttling.
- Android journey test: `integration_test/ui_journey_test.dart` drives registration/recovery acknowledgement, inspection, review, statistics, theme switching and locking. The driver in `test_driver/screenshots.dart` saves actual rendered screens to `screenshots/v1.1/`.
- Native file test: `integration_test/file_roundtrip_test.dart`, paired with `tool/drive_file_picker.py`, saves JSON through Android DocumentsUI, selects it again, verifies exact content equality, validates/restores the backup, saves CSV, and checks that cancelling returns no success.
- **Verified:** host test suite passed all 7 tests; real Android SQLite workflow passed; the visible Android journey passed; native file save/open/cancel passed. Layout coverage includes 320 px, portrait phone, tablet, and 844 × 390 / 1200 × 500 landscape onboarding. Device: Android API 36.1 emulator.
- Actual screenshots: [workspace](../screenshots/v1.1/dashboard.png), [station](../screenshots/v1.1/station.png), [record](../screenshots/v1.1/record.png), [recipes](../screenshots/v1.1/recipes.png), [statistics](../screenshots/v1.1/statistics.png), [dark settings](../screenshots/v1.1/settings-dark.png), [dark data management](../screenshots/v1.1/data-dark.png), [onboarding](../screenshots/v1.1/onboarding.png), [dark login](../screenshots/v1.1/login-dark.png).
- Build artifacts and detailed transient logs are under `build/`. Release packages use the existing development signing configuration.

### Historical package check — 1.1.0

`flutter build apk --release --target=lib/main.dart --target-platform android-arm64,android-x64 --split-per-abi` completed successfully. ARM64: 18.1 MB; x64: 19.5 MB. The x64 release APK was installed on the emulator and `am start -W` reported a successful cold launch into administrator setup. The release manifest contains no Internet permission. Minimum Android API is 24, target API is 36, version name is 1.1.0. [Release runtime capture](../screenshots/v1.1/release-onboarding.png).

SHA-256:

- ARM64: `04073BA04312D47E8080FE2F576C3B51C3748EB97FDCB9B5AE47ADEFB3809C48`
- x64: `96451ADA4CF8A1479765A38408202259303A1B9D2E3E6AE11EF6D53E73CE49B2`

The final analyzer reported no issues. The authentication regression also verifies that a database-write failure cannot prevent sign-out.

Device tests must run on a disposable emulator. Although the test databases have unique names, Flutter's integration runner installs/removes the complete app package; this was observed during these runs and can clear other data under that package.

For screenshots, run:

```sh
flutter drive --driver=test_driver/screenshots.dart --target=integration_test/ui_journey_test.dart -d <android-device>
```

For the native picker test, run `flutter test integration_test/file_roundtrip_test.dart -d emulator-5554 > build/file-roundtrip.log` and, in another terminal, `python tool/drive_file_picker.py`. The helper only taps the emulator's native picker for the generated test files. JSON and CSV fixtures are left in the emulator's chosen export folder for inspection.

## Environment notes

The existing machine has a stale global Gradle proxy (`127.0.0.1:7897`) and a stale `JAVA_HOME`. The successful direct build uses an existing JDK and command-scoped `-Dhttp.proxyHost= -Dhttps.proxyHost=` overrides. Project and plugin dependencies use the repository's existing Aliyun mirrors as well as standard Maven repositories. Kotlin incremental compilation is disabled to avoid the verified cross-drive cache failure when the Pub cache is on C: and the project on D:.

Release signing is still the repository's development signing configuration. Distributable store releases need the project's own signing key. No publishing or remote deployment is performed by this work.

Set `LINESIGHT_DIRECT_NETWORK=1` for builds on this workstation. The project Gradle wrappers then pass explicit direct-network properties, and Android repositories use Aliyun mirrors. This is opt-in and does not edit the user's global Gradle or proxy settings. Normal `flutter` commands already locate the installed Android Studio JDK; a direct `gradlew` command additionally needs a valid `JAVA_HOME`.

When switching from integration tests to a release build, use `flutter build apk --release` with its default pub step. Flutter 3.44 regenerates the native plugin registrant during that step to remove development-only plugins; using `--no-pub` immediately after integration tests leaves the test plugin in the old registrant and fails the release Java compilation. Do not edit generated registrants manually.

## Version 1.1.1 implementation

- Added optional structured audit targets, stable actor IDs, export operation IDs and before/after values. SQLite and JSON schema numbers remain 1; old entries still load. Records now show their bulk archive/restore history accurately, with paginated drilldowns and searchable audit targets.
- Export start is persisted before opening the native picker. Its one-use completion ticket can append an outcome for the initiating account even when locked; it cannot authorize business operations or restore a session. The workbench result notice is visible only to that account and lasts for the current process.
- Background locking now has a monotonic elapsed timer and checks both on resume and when an operation resumes before the lifecycle callback. Backup import requires the same authenticated administrator session after selection and file reading. Password changes, delayed simulation, account creation and queued preference updates also bind asynchronous work to the initiating session.
- `flutter analyze --no-pub` reported no issues, and normal-entrypoint ARM64/x64 release compilation succeeded. No tests were added or run in this continuation. Logs: `build/analyze-1.1.1.log` and `build/release-1.1.1.log`. Prior test results and screenshots above are historical evidence for 1.1.0, not runtime verification of 1.1.1.

### Previous installable packages — 1.1.1

Versioned copies of this earlier checkpoint are retained under `build/releases/1.1.1/`. Android minimum API 24, development signing configuration retained. Version name 1.1.1; split APK version codes are 2003 for ARM64 and 4003 for x64.

| Package | Bytes | SHA-256 |
|---|---:|---|
| `LineSight-1.1.1-arm64-v8a.apk` | 19,002,297 | `25967C2DBC6E7E0920ECC1AC4DAFF0CD426367B136AA2CA37FA7206A91C8846D` |
| `LineSight-1.1.1-x86_64.apk` | 20,476,047 | `A784401730982F7589F828C6656BA1A1358FB08120E5EF06CD9D8DF783053ECD` |

The packages were compiled from `lib/main.dart`. This continuation did not install or run them on the emulator.

## Version 1.1.2 — restore previews and data protection

Added compact bounded JSON export, bounded native reads, off-thread parsing and comparison, file metadata, per-object added/changed/removed lists, field-level comparisons, audit collision counts, revision-bound confirmation, persistent restore-point metadata, undo impact previews and a persistent local backup-save receipt. Existing schema-1 backups and old undo snapshots remain readable. New route navigation clears stale snackbars, and glass-panel text/app-bar foregrounds explicitly use the active theme.

Validation in this continuation:

- Host suite: 16 tests passed, including prior navigation/auth layouts, new backup/UTF-8 size/validation/diff checks, enlarged-text 320 px and tablet detail layouts, and theme foreground behavior.
- `data_management_test.dart`: real SQLite passed, including forced transaction failure preserving original workspace and undo point, restarting with point/receipt metadata, old point metadata fallback, stale preview and stale point rejection, imported-object ownership and one-use export tickets attributed to their initiating account.
- `local_workflow_test.dart`: existing Android authentication, role, inspection, backup, recovery and sign-out regression passed against the new store implementation.
- `picker_lock_test.dart`: Android DocumentsUI stayed open for 35 seconds; the app locked, file save completed under the original actor, re-login showed the result, and the saved file could be reopened and parsed.
- `restore_journey_test.dart`: visible difference drilldowns, restore to 96 records, undo back to the exact 97-record ID set, record history and audit detail navigation passed. The driver emits actual light/dark captures into `screenshots/v1.1.2/`. [Gallery](../screenshots/v1.1.2/README.md).

The UI test exposed a previous-page snackbar obscuring a new page's confirmation action; navigation now clears it. Screenshot review also exposed insufficiently explicit dark foregrounds; glass text and app-bar colors were corrected and the journey adds foreground assertions. Test-helper waits were corrected to avoid waiting for a busy button's animation while its confirmation dialog is open. These interrupted/failing intermediate runs are not counted as passes; final successful run logs are retained under `build/`.

Logs: `build/host-1.1.2.log`, `build/data-management-1.1.2.log`, `build/local-workflow-1.1.2.log`, `build/picker-lock.log`, `build/restore-journey-1.1.2.log`. Android device: disposable API 36.1 emulator, `emulator-5554`.

### Previous installable packages — 1.1.2

Final static analysis reported no issues. The normal `lib/main.dart` release build succeeded for both ABIs. The x64 release APK was installed and cold-launched successfully into administrator setup (`am start -W`: `Status: ok`, `LaunchState: COLD`). Its manifest has no Internet permission. Android minimum API 24, target API 36; development signing configuration retained. [Release launch capture](../screenshots/v1.1.2/release-onboarding.png).

Versioned files are under `build/releases/1.1.2/`. These versioned copies retain this checkpoint. Version name 1.1.2, split version codes 2004 (ARM64) and 4004 (x64).

| Package | Bytes | SHA-256 |
|---|---:|---|
| `LineSight-1.1.2-arm64-v8a.apk` | 19,068,033 | `B48109AAAD2139545633BDA0D611476F569448A2E43AB0818C40D1688CDF96C4` |
| `LineSight-1.1.2-x86_64.apk` | 20,541,779 | `461915D5FEF727DF80F0C7BBF95E8DEBE997C774C321B072F79F866114877AE9` |

Additional logs: `build/analyze-1.1.2.log`, `build/release-1.1.2.log`. The final host suite passed all 16 tests and the final visible journey passed with foreground assertions on both panel text and the actual back-button icon.

## Version 1.1.3 — portable timestamps and local dates

[Compatibility and behavior](CHANGELOG_1.1.3.md). UTC serialization now covers business timestamps, reviews, audits, restore points and local backup receipts. The dashboard, records, audit ranges and daily chart buckets use local calendar dates. CSV headers state UTC. Precise detail and comparison timestamps include seconds, fractional seconds and the applicable offset.

Older JSON files retain their original text through the preview and require an explicit source-time choice plus acknowledgement. The resulting audit records that choice. Existing SQLite data is normalized with a transactionally retained archive of the original workspace, undo point and point/receipt metadata. The new **数据管理 → 时间与日期** page explains the upgrade assumption and supports exporting original snapshots without overwriting the current backup-save receipt.

Validation:

- Final host suite: **24 tests passed**, including canonical/mixed offsets, precision, invalid dates/offsets, repeated reinterpretation of original strings, equivalent-instant restore comparisons, local date boundaries, original archive preservation, UTC CSV values and consistency between the shared UI version label and pubspec. Detail layout coverage now includes the legacy-time selector, interpreted preview and time-storage screen at 320 px with 1.5× text and 1100 px.
- Android `time_portability_test.dart`: passed on a disposable emulator configured to `America/New_York`, with actual 23-hour and 25-hour dates, skipped/repeated clock-time parsing, forced SQLite migration rollback, retained exact originals, reopen without repeated migration, restore/undo, permission-bound store guard, visible timezone selection/acknowledgement and restore audit verification. The emulator's prior `GMT` timezone was restored afterward.
- Existing `data_management_test.dart` and `local_workflow_test.dart` both passed against the updated timestamp storage, including authentication, permissions, review/archive, restore/undo, persistence and failed-transaction protection.
- Actual UI capture: [legacy-time preview](../screenshots/v1.1.3/legacy-time-preview.png). The screenshot was checked for complete choice, original/interpreted timestamp and acknowledgement visibility. Test scroll helpers explicitly target the page scroll view, avoiding selectable timestamps' internal scroll areas. Initial helper failures are not counted as passes.

Logs: `build/host-1.1.3.log`, `build/time-portability-1.1.3-final.log`, `build/regression-1.1.3.log`. The native file-picker lock journey was verified in 1.1.2 and was not rerun for this timestamp checkpoint.

### Previous installable packages — 1.1.3

Final static analysis reported **No issues found**. The normal `lib/main.dart` ARM64/x64 release build succeeded. The final x64 package was installed and cold-launched (`Status: ok`, `LaunchState: COLD`) into administrator setup. Its manifest has no Internet permission. Android minimum API 24, target API 36; development signing retained. Version name 1.1.3, split version codes 2005 (ARM64) and 4005 (x64). [Release launch capture](../screenshots/v1.1.3/release-onboarding.png).

The versioned copies under `build/releases/1.1.3/` match Flutter's standard output packages. Earlier versioned packages remain available.

| Package | Bytes | SHA-256 |
|---|---:|---|
| `LineSight-1.1.3-arm64-v8a.apk` | 19,068,093 | `2C1F1D80D9AC0C28E08AD1A14852B80A878CAC781C4E118FE09E309EFF0664BF` |
| `LineSight-1.1.3-x86_64.apk` | 20,541,839 | `6E6192B4E016B65D9A0CF691D6F849B35B41DDB5081753147530B2A830EF5EC6` |

Additional logs: `build/analyze-1.1.3.log`, `build/release-1.1.3.log`. The login/settings version labels were unified after release screenshot review, then the 24-test host suite, static analysis, both release builds and cold launch were repeated. No external publication was performed.

## Version 1.1.4 — complete backups and large local state

[Format and compatibility details](CHANGELOG_1.1.4.md). Added LSB 2 complete backups, a format-selection page, preparation/read progress and cancellation, verified import followed by the existing restore preview, and Android streaming saves with destination readback. Successful LSB receipts include format, byte count and whole-file SHA-256. The export snapshot is captured when backup starts; subsequent changes need another backup. Native save completion remains attributed to the initiating account after automatic locking.

SQLite schema 2 splits large state into bounded text chunks while keeping manifests, account changes, workspace changes and undo points in their existing transactions. Version-1 oversized single-cell values are read through bounded SQL slices during upgrade. UTF-16 chunk boundaries preserve surrogate pairs, and reassembly checks order, length and SHA-256. A missing chunk fails startup without resetting local accounts or the database.

Validation:

- Final host suite: **30 tests passed**, including complete round trips beyond 20 MiB, all audit targets/changes, microsecond timestamps, byte hashes, truncated/corrupted/trailing content, count/ownership/UTC checks even after checksum recomputation, limits, early and completion-time cancellation cleanup, empty histories, old receipt compatibility, and theme changes on the backup route. Layout checks cover 320 px with 1.5× text and tablet widths.
- Android `large_backup_test.dart`: passed with a real version-1 database containing a workspace over 20 MiB. Verified schema upgrade, exact legacy-cell reads, chunked subsequent writes, Unicode boundaries, forced insert failure rollback, LSB restore, reopen preserving all 1,800 fixture audit IDs, large undo-point reads/undo and consumed-chunk cleanup. Deliberately removing a workspace chunk causes startup error while accounts remain stored.
- Android `archive_picker_test.dart`: actual DocumentsUI save/open/cancel passed with a complete backup over 20 MiB (approximately 22.9 MB). The picker stayed open for 35 seconds, automatic lock took effect, the original actor retained the receipt, re-login displayed the result, and reopening the selected file preserved exact business objects. Wrong native digest was rejected, failed/cancelled saves preserved the previous receipt, scratch files were cleaned up and the receipt survived database reopen.
- Existing Android `data_management_test.dart` and `local_workflow_test.dart`: passed against schema 2, including transactional rollback, restore/undo, stale previews, original-actor export attribution, local authentication, account roles, password recovery, locking and restart persistence.
- Android `archive_import_journey_test.dart`: visible verification → preview → confirmation → restore passed. Restoring changes 97 records to 96 with a 97-record undo point; corrupted input displays an error without changing the revision, and locking during import prevents preview/write. Fresh light/dark and valid/invalid import screenshots were visually checked. [Gallery](../screenshots/v1.1.4/README.md).
- Android `time_portability_test.dart`: both tests passed with the emulator set to `America/New_York`, covering real 23/25-hour calendar days, skipped/repeated clock times, atomic preservation of legacy originals, migration rollback, reopening, explicit time interpretation, restore/undo and permission checks. The previous `GMT` timezone was restored afterward. Log: `build/time-portability-1.1.4.log`.

Logs: `build/host-1.1.4-final.log`, `build/large-backup-1.1.4.log`, `build/archive-picker-1.1.4-final.log`, `build/archive-picker-driver-1.1.4-final.log`, `build/regression-1.1.4.log`, `build/archive-import-1.1.4-capture-final.log`. Intermediate failed picker runs are retained for diagnosis and are not counted as passes. The native helper now rejects stale UI XML when `uiautomator dump` fails to reach idle state. The screenshot helper flushes the image surface before capture; early images showed stale route/theme frames despite passing state assertions. Final screenshots show the settled screen, and explicit rendered-text assertions pass.

The active model still resides in memory. **256 MiB is a file-format limit, not a measured capacity promise for all devices.** LSB preserves all supported records and audit history; it does not prune data. Credentials, preferences, undo points and the separate pre-time-upgrade originals remain outside business backups. Compatible JSON and original-time exports retain their 20 MiB limit; CSV retains its earlier whole-content export path. Older releases cannot open the upgraded SQLite database.

### Previous installable packages — 1.1.4

The final analyzer reported **No issues found**. Normal-entrypoint ARM64/x64 release compilation succeeded from `lib/main.dart`. Both manifest checks show version name 1.1.4, minimum Android API 24, target API 36 and no Internet permission. Split version codes are 2006 (ARM64) and 4006 (x64). The existing development signing configuration is retained.

Versioned copies under `build/releases/1.1.4/` were hash-compared against Flutter's standard output packages; `checksums.json` records the same values. Earlier versioned packages are retained.

| Package | Bytes | SHA-256 |
|---|---:|---|
| `LineSight-1.1.4-arm64-v8a.apk` | 19,264,701 | `C0E64AD32FB700F7200AC598028AFB4B29B6F22957D5F1767FA7C4145A6718B4` |
| `LineSight-1.1.4-x86_64.apk` | 20,738,447 | `B213B84B9EA4884FE2A885A06EB85948B238081516E5F677DC07BAC00202817B` |

Build/analysis logs: `build/analyze-1.1.4-final.log`, `build/release-1.1.4.log`, `build/manifest-arm64-1.1.4.log`, `build/manifest-x64-1.1.4.log`.

The final x64 release APK was installed on the disposable emulator and cold-launched successfully (`Status: ok`, `LaunchState: COLD`). The administrator-setup screen and visible 1.1.4 version label were checked in the [release capture](../screenshots/v1.1.4/release-onboarding.png). Logs: `build/install-1.1.4.log`, `build/cold-launch-1.1.4.log`. [Six-screen overview](../screenshots/v1.1.4/overview.jpg). No external publication was performed.

## Version 1.1.5 — authenticated startup recovery

[Behavior, compatibility and LSR format](CHANGELOG_1.1.5.md). Startup now identifies the failed read stage and keeps retry bound to the original database. When an enabled administrator can be read, password or recovery-code verification grants a separate recovery session. This session cannot perform normal business operations and locks after 30 seconds away regardless of the normal auto-lock preference.

Validated LSB/JSON selection leads to an explicit recovery preview. Legacy timestamps still need an interpretation and acknowledgement. One SQLite transaction rechecks the administrator, preserves every raw state/chunk row, writes the backup workspace and recovery audit, and verifies the session again. Failure rolls back both preservation and replacement. Success retains account credentials and requires normal login. Valid preferences and time archives remain usable; invalid state, old undo points and receipts stay in preserved originals.

Administrators can inspect recovery history and export byte-exact LSR originals with progress, cancellation and native save/readback verification. Original exports identify the recovery record in the audit and do not replace the business-backup receipt. An offline Python reader verifies or extracts those files without touching the database. These archives exclude the account table, are unencrypted, and cannot be imported as business backups. No automatic deletion or retention cleanup is performed.

Validation:

- Final host suite: **33 tests passed**, including all recovery pages at 320 px with 1.5× text and dark tablet width, administrator-unavailable help without credential fields, exact sub-kilobyte size labels, complete-backup integrity/limits, portable timestamps and existing navigation/restore layouts.
- Final static analysis: **No issues found**. A missing-brace style diagnostic was corrected; no runtime behavior changed.
- Android `storage_recovery_test.dart`: both tests passed with real SQLite. Coverage includes approximately 3 MiB malformed raw state, invalid UTF-8 and embedded NUL, orphan chunks, retry path, password/recovery-code checks, persisted throttling, disabled/non-admin denial, unavailable account storage, blocked regular operations, unresolved legacy time, stale sessions, forced transaction rollback, exact original reconstruction, export cancellation/size-limit cleanup, unchanged credential verifiers and successful reopen.
- Android `storage_recovery_legacy_test.dart`: passed visible source-time selection and acknowledgement, fixed UTC+08 recovery, preservation of malformed preferences and invalid time archives, and usable default preferences afterward.
- Existing `data_management_test.dart`, `local_workflow_test.dart` and `large_backup_test.dart`: passed against schema 3. The combined run finished **6 tests passed**, covering existing restore/undo/authentication/permissions plus a version-1 workspace over 20 MiB, chunked writes, rollback, restoration, reopening and missing-chunk detection.
- Offline LSR reader: **4 tests passed**, including exact invalid-byte extraction, path-like keys with generated filenames, damaged/truncated/trailing records, recomputed-hash segment/count errors, existing-directory refusal and no final extraction on invalid input. It also verified and extracted the final native-saved 714-byte LSR containing the 35-byte damaged workspace fixture.
- Final Android `storage_recovery_journey_test.dart`: actual backup save, recovery authentication, open-picker expiry after 35 seconds with normal auto-lock disabled, reauthentication, native selection, integrity preview, acknowledgement/confirmation, recovery and normal login all passed. Navigation through Data Management to recovery history/original detail, native save with a second 35-second lock, initiating-actor completion with recovery ID, exact file reopen and native cancellation also passed. The final runner completed in 3:22; its `+2` includes framework teardown, representing one end-to-end scenario. Fresh captures show the final routes and the corrected **35 B** size in dark mode.
- Android `time_portability_test.dart`: **2 tests passed** with `America/New_York`, including 23/25-hour calendar days, skipped/repeated clock times, atomic migration and original preservation, forced rollback, reopening, legacy time acknowledgement, restore/undo and permission checks. A `finally` block restored the prior `GMT` timezone; `build/timezone-1.1.5.json` records both values and the zero test exit code.

Logs: `build/host-1.1.5-final.log`, `build/analyze-1.1.5-final.log`, `build/regression-1.1.5.log`, `build/recovery-reader-tests-1.1.5-final.log`, `build/recovery-reader-1.1.5-final.log`, `build/time-portability-1.1.5.log`.

Native journey logs: `build/storage-recovery-journey-1.1.5-final.log`, `build/storage-recovery-picker-1.1.5-final.log`, `build/recovery-reader-native-1.1.5-final.log`. [Recovery gallery](../screenshots/v1.1.5/README.md). Earlier successful native runs remain available; final captures replace their screenshots after checking route/theme and byte-size rendering.

Recovery requires readable account tables and a SQLite transaction that can copy/write application-state tables. It does not repair structural SQLite corruption or failing storage. Original archives consume additional local space and are lost if app data is cleared or the app is uninstalled. SQLite schema 3 requires version 1.1.5 or newer; business backup formats remain LSB 2 and JSON 1.

### Previous installable packages — 1.1.5

Normal-entrypoint release compilation succeeded from `lib/main.dart` for ARM64 and x64. Both manifest checks show version name 1.1.5, minimum Android API 24, target API 36 and no Internet permission. Split version codes are 2007 (ARM64) and 4007 (x64). The repository's development signing configuration is retained.

Versioned packages under `build/releases/1.1.5/` were hash-compared with Flutter's standard build outputs. `checksums.json` records these exact values; earlier versioned packages are retained.

| Package | Bytes | SHA-256 |
|---|---:|---|
| `LineSight-1.1.5-arm64-v8a.apk` | 19,330,269 | `2FBAB56A0427B017728D63252CAE08D082B449FFF53CF4D8DC7EC71A300059EF` |
| `LineSight-1.1.5-x86_64.apk` | 20,804,015 | `6E3898BD509DBB3993D5AA7D239A0A2C34BC70A7D0C978CAF1FE6439D86B0406` |

The x64 APK installed successfully on the disposable emulator and cold-launched into administrator setup with a visible **1.1.5** version label. The initial launch and two repeated force-stop/launch checks all reported `Status: ok`, `LaunchState: COLD`. Android's `TotalTime` values were 14,189 ms for the first launch after installation, then 3,646 ms and 3,754 ms. These are observations from this emulator, not a physical-device performance guarantee; large-workspace startup profiling remains continuing work.

Logs: `build/release-1.1.5.log`, `build/manifest-arm64-1.1.5.log`, `build/manifest-x64-1.1.5.log`, `build/install-1.1.5.log`, `build/cold-launch-1.1.5.log`, `build/cold-launch-1.1.5-repeat-1.log`, `build/cold-launch-1.1.5-repeat-2.log`. [Release capture](../screenshots/v1.1.5/release-onboarding.png) · [Six-screen overview](../screenshots/v1.1.5/overview.jpg). No external publication was performed.

## Version 1.1.6 — streamed CSV and export previews

[Behavior and limits](CHANGELOG_1.1.6.md). All four CSV routes show an immutable selection, counts, format rules and sample rows. Worker generation uses approximately 64 KiB batches with progress/cancellation. Android streams `text/csv` and verifies destination size/SHA-256. The 15 columns, BOM, CRLF, quotes and UTC precision remain; formula protection includes leading whitespace. Session checks and one-use completion retain the initiating actor after locking. Audit details show a file-verification card and clear label/value spacing. CSV never replaces the business-backup receipt.

Validation:

- **42 host tests passed**: immutable snapshots, exact fields/ordering, all entry routes, 4,000-row output over 20 MiB, empty output, limits/cancellation cleanup, 320 px enlarged-text and dark-tablet layouts, audit metadata and spacing.
- Static analysis: **No issues found**. Intermediate BOM-decoder, lazy-row and const test corrections are not counted as successful runs.
- **4 Android regressions passed**: data management, local workflow and both storage-recovery cases; authentication, permissions, rollback, restore/undo, sessions, exact originals and reopening.
- Final native CSV journey passed in **3:33**: real review after preview, 35-second picker lock, original-actor completion, exact reopen, filtered selection, cancellation, stale/locked denial, missing/wrong verification rejection, receipt preservation and persisted metadata. Runner `+2` includes teardown (one scenario).
- Python independently checked every field/order of **24,611,792 bytes, 4,000 rows, 15 columns**. SHA-256: `36931e76dd603e2bb7f27365e6e3aa02d9218a62a8d99a488cc92f87edc53ab0`.
- Final native LSB regression passed in **3:33**: file over 20 MiB, readback, locking, exact reopen, cancellation, bad hash, cleanup and persisted receipt.

### Current installable packages — 1.1.6

Final packages and reports: `C:/Users/29668/LineSight-releases/1.1.6/`. D: reached zero free bytes, so source was copied and hash-verified before C: compilation. A cache-deletion attempt was rejected by automatic policy; no deletion occurred. `reports/BUILD_LOCATION.md` records the location and source proof. Original source and earlier releases remain on D:.

Normal `lib/main.dart` ARM64/x64 release compilation succeeded. API 24 minimum, target 36, no Internet permission, existing development signing. Version 1.1.6+8; split codes 2008/4008. Package copies match build-output hashes:

| Package | Bytes | SHA-256 |
|---|---:|---|
| ARM64 | 19,330,265 | `5FF40FCEDE96CA33D0000172DDEFEC133FB46D48FB777E831FAB0741C63DA862` |
| x64 | 20,869,547 | `5EC17B6AD98A49BEBC485D43A775738DDF69367097CCD5D13CF694AE24C9775D` |

The x64 APK installed and cold-launched into administrator setup showing 1.1.6. Initial/repeated cold-launch `TotalTime`: **16,081 / 3,249 / 3,305 ms**, all `Status: ok`. These are emulator observations. Release `screenshots/overview.jpg` shows six checked captures; `screenshots/README.md` provides the gallery.

Release `reports/` retains final host/analyzer/Android/CSV/independent-reader logs, LSB journey/driver logs, build/manifest/install/cold-launch logs and source-copy verification. D: retains the original CSV fixture and earlier logs. No external publication occurred.

The model, CSV snapshot and whole-workspace audit transactions still use memory/time. CSV limit: 256 MiB/file, 16 MiB/row; this is not a device-capacity guarantee. SQLite remains schema 3; business formats remain LSB 2/JSON 1. Startup and transaction profiling continue.

## Continuing work under the active app-development goal

The first installable offline version and the validation listed above are complete. Continue the user's requested expansion and refinement:

1. Large complete backups are implemented in 1.1.4 and streamed CSV in 1.1.6. Continue measuring large-model startup and transaction costs: the model remains in memory, and the 256 MiB format limit is not a device-capacity guarantee. Pre-time-upgrade original JSON exports still use the earlier whole-content path. The large CSV journey also exposes the cost of whole-workspace audit transactions, which remain a performance target.
2. Continue secondary-page and accessibility refinements, preserving local account/data workflows and sample-data labels. Current evidence covers the new restore and audit routes, not every possible data volume or display configuration.
3. Authenticated application-state recovery is implemented in 1.1.5. Continue observing storage and recovery usability; physical SQLite corruption and failing storage remain outside the automatic recovery workflow.

Keep the original scope: complete local authentication, data management, all associated screens and secondary workflows, and further UI/interaction improvements. The broader user goal remains active.
