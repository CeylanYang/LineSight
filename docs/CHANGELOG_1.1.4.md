# LineSight 1.1.4 — complete backups beyond 20 MB

## Backup and restore

**数据管理 → 保存完整备份** now opens a format-selection page. LSB is the default complete business backup, with a 256 MB file limit. Compatible schema-1 JSON remains available up to 20 MB. Neither format drops old records or logs to fit a limit; an oversized export fails before opening the save picker.

LSB contains recipes, stations, all inspections (including archived examples), all audit events and every structured target/change. It excludes local credentials, preferences, backup receipts, restore points and the separate pre-time-upgrade originals, consistently with the business-backup boundary. LSB requires version 1.1.4 or later. The format is unencrypted; its SHA-256 check detects content changes and incomplete transfers, and is not an authenticity signature.

LSB preparation and reading run in a worker isolate with progress and cancellation. The writer emits one item at a time to an app-private temporary file. Android's system save dialog copies that file using a 64 KB buffer, closes the output, then reads the destination back and verifies its byte count and SHA-256 before returning success. It does not send the entire file through the Flutter platform channel. Export completion retains the initiating account when the picker stays open beyond the automatic-lock interval. Cancellation and failure do not replace the previous successful backup receipt.

Selecting either JSON or LSB opens a read/check page and then the existing object-by-object restore preview. Checks finish before workspace mutation. Restore remains administrator-only, bound to the authenticated session and compared revision; the current workspace is saved as a transactional undo point. LSB preview displays a passed integrity check. The last successful LSB receipt records format, size and whole-file checksum.

Temporary exports are removed after save/cancel/failure. The next export also attempts cleanup of feature-owned cache directories older than 24 hours, excluding active jobs. Native output failure may leave a file at the user-selected destination; it is not reported as a successful backup and the app does not delete that destination automatically.

## SQLite storage

Database version 2 adds `state_chunks`. Small state values remain direct text. Large workspace, undo and migration-archive values use 128 Ki UTF-16-unit chunks with a small manifest recording ordered chunk count, total units and SHA-256. Splits preserve surrogate pairs. Business changes, account changes, chunks, manifests and undo metadata share their existing transaction. Undo removes its consumed point's chunks.

Version-1 single-cell values are read in bounded SQL `substr` calls, including large historical cells that cannot be returned through one Android cursor-window row. No old workspace is reset during upgrade. Missing, reordered or changed chunks produce a startup error with existing data retained. **Older releases cannot open a version-2 database**; compatible JSON export is the route for moving business data into an older app installation.

The application still holds the active domain model in memory, and comparison/restore may need additional copies. The 256 MB limit is a file-format limit, not a guarantee that every maximum-sized workspace fits every device. Import/export use matching file and item limits. Original schema-1 time-archive exports and compatible JSON remain limited to 20 MB. CSV continues to use the existing export path.

## LSB 2 format

- UTF-8, LF-delimited records. First line is exactly `LINESIGHT-BACKUP/2`.
- A `manifest` line identifies app/schema/export time and exact counts for `recipe`, `station`, `inspection`, `audit`, `target`, `change`.
- Recipe, station and inspection rows appear in that order. Each audit header is immediately followed by its targets and then its changes. Child rows carry the audit ID. Audit arrays are emitted as separate rows to avoid a large batch event becoming one oversized JSON object.
- All time fields use UTC with `Z`.
- The last line is a `checksum` with algorithm `SHA-256`, payload byte count and payload digest. The payload includes every byte before this final line, including line breaks. The checksum line also ends with LF; extra content is rejected.
- Limits: 256 MiB file; 16 MiB single line; existing workspace limits of 200 recipes, 100 stations, 100,000 inspections and 100,000 audit entries. Each audit supports up to 100,000 targets and 30 changed fields. Limits reject entire operations; no truncation occurs.

See [LOCAL_WORKSPACE.md](LOCAL_WORKSPACE.md) for current verification results and final artifacts.
