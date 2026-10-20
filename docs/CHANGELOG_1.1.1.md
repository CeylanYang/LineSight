# LineSight 1.1.1 — traceability and file completion

## User-visible changes

- Record, station and recipe histories use stable object IDs. Bulk archive/restore events appear on every affected record. Labels in a log keep the names used at the time of the operation.
- New audit detail page links to current records, stations and recipes, shows removed objects, supports searching large target lists, and exposes selectable event/actor/export IDs.
- Recipe edits, station naming, changeovers and quality reviews retain before/after values. No password, password hash or recovery code is included.
- Audit search includes object names and IDs, with action and 7/30-day filters. Record and recipe details show the five most recent events and a complete-history link. Stations have a history action.
- Native CSV/JSON export records a start event and a saved/cancelled/failed result. The two events share an operation ID. An interrupted application leaves a start event with an explicitly unknown result.
- Export completion remains attributed to the original account after automatic locking. A dismissible result card is shown to that account on the workbench, including after re-login within the same application process.
- The 30-second background lock uses elapsed time and a timer, with an additional elapsed-time check before resumed operations. Backup selection rechecks the initiating session after both picker completion and file reading.

## Compatibility and implementation boundaries

SQLite stays at version 1 and JSON backups keep schema 1. Audit entries add optional `actorId`, `operationId`, `targets` and `changes` fields; missing fields in old data load as absent/empty. Old record reviews and simulated inspections can be associated through their original identifier format. Old bulk logs containing only a count cannot be assigned to individual records retrospectively.

Historical targets are allowed to outlive their objects, including after sample clearing, backup restore and undo. Imported account IDs describe the originating workspace; business backup does not create local accounts. The mutable, unencrypted local database is not a tamper-evident audit system.

An export ticket authorizes only one result entry for an already-authorized operation. It cannot alter business data, restore authentication or take the identity of a later session. Completion waits for an active database mutation before appending its result. File writes and the SQLite log are separate operations; if the log write fails after a successful save, the account's result card states both outcomes. Result cards are in memory; successfully written audit events persist.

## Evidence for this revision

Static analysis and release-build results are recorded in `LOCAL_WORKSPACE.md`. The existing host and Android test evidence belongs to the 1.1.0 checkpoint. No new tests were added or run for 1.1.1. In particular, prolonged backgrounding with the native picker and the new audit navigation still need device regression evidence. Existing `screenshots/v1.1/` images show the previous checkpoint.
