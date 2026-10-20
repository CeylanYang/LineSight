# LineSight 1.1.2 — backup and restore workspace

## Changes

- Complete JSON backups use compact encoding, retaining all inspection records, archived records, recipe snapshots and audit events. Export and import enforce the same 20 MB UTF-8 byte limit. Oversized exports fail before opening the native save dialog, rather than producing a backup this version cannot import.
- Native backup reads enforce the size limit while reading, in addition to checking the picker metadata. Parsing, validation, export encoding and restore comparisons run off the UI thread where invoked by the UI.
- Restore previews show file size/time, added/changed/removed objects, unchanged counts, and audit merge behavior. Object groups lead to searchable, paginated lists and field-level before/after pages. Equal record counts no longer obscure content changes.
- Conflicting audit IDs retain the original local event, matching the existing store merge rule. The preview states the conflict count.
- A restore confirmation is tied to the workspace revision shown in the preview. If another operation finishes during confirmation, the user must inspect the refreshed preview and confirm again.
- Restore points retain creation time, creator and object counts in the same SQLite transaction as the restore. Old restore-point snapshots remain readable. Data management shows a point only when one exists, and undo has its own impact preview and optional current-data export.
- Undo consumes the exact previewed restore point and keeps current audit history. Restoring a different backup replaces the previous point; the preview says so. Incoming objects are copied before committing to prevent later caller edits from changing stored workspace state in memory.
- The most recent successful JSON save has a local, persistent receipt with time, initiating person and record count. Cancellation does not replace it, imported audit events do not create it, and it does not claim the external file still exists.
- Navigation clears prior snackbars so a restore-success message cannot obscure actions on the next page. Glass-panel text and app-bar foregrounds explicitly follow the active theme for readable dark details.

## Boundaries

Backups remain plaintext schema-1 JSON. Accounts, password/recovery material, preferences, local save receipts and local undo-point metadata are not exported as account/state data. Audit history still includes actor labels and IDs. The 20 MB limit is a current supported-file limit; no history is silently truncated. Larger workspaces still require expanded backup support. CSV exports do not provide a full workspace restore.

The receipt records a completed save, not current backup freshness or ongoing access to the external file. A restore point lives in the app's local database and is removed with app data; it is not a substitute for an external backup.

## Verification sources

- `test/backup_test.dart`: compact roundtrip, old schema compatibility, UTF-8 file limits, audit extensions and invalid payloads, equal-count differences and audit merge counts.
- `test/restore_layout_test.dart`: new preview/list/detail and audit screens at 320 px with enlarged text and tablet width.
- `test/theme_test.dart`: dark body/icon colors and inherited text updates on a pushed route after a theme change.
- `integration_test/data_management_test.dart`: real SQLite restore/undo, point and receipt persistence, stale revisions, restored-object ownership, audit linking, original-account export attribution, one-use ticket behavior and forced transaction failure.
- `integration_test/picker_lock_test.dart`: actual Android DocumentsUI held open for 35 seconds, authentication locking, original-actor completion, login feedback and reopening the saved JSON.
- `integration_test/restore_journey_test.dart`: visible change drilldowns, restore confirmation, undo confirmation and audit screens. The screenshot driver accepts `LINESIGHT_SCREENSHOT_DIR` for versioned galleries.

Execution results and release hashes are recorded in `LOCAL_WORKSPACE.md` after the runs finish.
