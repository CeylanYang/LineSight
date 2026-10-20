# LineSight 1.1.7 — startup responsiveness

## Loading workspaces

Startup decodes and validates business state in a worker isolate. Each stored JSON document is decoded once; the validated workspace and small restore-point summary are reused. Ordinary startup no longer serializes normalized workspaces that do not require a legacy-time migration. A full undo snapshot is still validated even when its metadata exists.

Original raw strings and normalized legacy timestamps still commit together in one SQLite transaction. Preferences and all other state must validate before this transaction is prepared. Invalid settings therefore cannot cause a partial migration. The store publishes the loaded model only after the transaction succeeds; local login remains required.

SQLite stays at schema 3. LSB, JSON, CSV and LSR formats, account credentials, permissions, and export receipts are unchanged. Unknown JSON fields survive legacy migration, and canonical startup preserves exact stored text without writing.

## Startup interface

The startup screen now uses the app's branding and displays the current account-read, record-read, validation or legacy-preservation step. Status changes are exposed as a screen-reader live region. Reduced-motion settings use a static hourglass. Narrow screens, enlarged text, landscape and dark tablets remain scrollable without overflow.

## Scope and measurement

This removes duplicated decode/validation and unnecessary JSON encoding, and moves remaining parsing away from the UI isolate. SQLite reads, chunk integrity checks, isolate transfer and legacy-migration writes still consume time. The model remains in memory. Whole-workspace business transactions are a separate continuing performance target.

`integration_test/startup_profile_test.dart` records three runs for a small workspace, a 22.7 MB workspace and the same workspace with an equally large undo point. It verifies full model equality, exact canonical source preservation, metadata and no migration writes using a SQLite trigger. A 16 ms timer measures main-isolate heartbeat gaps; these are scheduling observations, not rendered-frame measurements. Debug-emulator observations must not be presented as release-device speed guarantees.

Final validation and package evidence are recorded in `LOCAL_WORKSPACE.md` and the release reports.

