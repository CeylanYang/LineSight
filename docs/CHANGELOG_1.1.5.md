# LineSight 1.1.5 — authenticated startup recovery

## Recovery when the workspace cannot open

The startup error screen now explains the failed stage, retains retry, and offers administrator verification when the local account table can be read. Retry retains the original database path. A missing workspace is treated as an error; the app does not silently create an empty workspace over existing accounts.

Recovery verification accepts an enabled administrator's password or existing recovery code. It shares the normal account failure counter and one-minute throttle after five failures. A recovery code proves access for this operation and does not change the password. Recovery access is separate from a normal signed-in session, cannot perform business operations, and always locks after 30 seconds away from the app, including when normal automatic locking was disabled. Native selection, reading, preview and the final write remain bound to the verified session.

The administrator selects an existing LSB or JSON business backup. The file passes the existing size, format, count, reference and integrity checks before a recovery confirmation page opens. Older JSON times still require an explicit source-time interpretation and acknowledgement. The screen shows the backup's timestamp and counts, and explains that current unreadable data cannot be reliably compared or merged. Backup contents determine the recovered workspace; later changes are not automatically reconstructed.

## Atomic preservation and replacement

SQLite schema 3 adds `recovery_snapshots`, `recovery_state` and `recovery_chunks`. Existing schema 1/2 databases upgrade without resetting accounts or business data. Schema 1 large text values continue to use the bounded reads introduced in 1.1.4. Older app releases cannot open a schema-3 database.

One transaction:

1. Rechecks that the verified account is still an enabled administrator.
2. Copies all current `state` cells and `state_chunks` rows into an immutable recovery snapshot using SQL, including malformed values and orphaned chunks.
3. Writes the validated backup workspace and a new recovery audit entry.
4. Retains readable boolean preferences and valid time-upgrade archives. Old restore points, backup receipts and other state remain in the preserved originals; they are not activated in the recovered workspace.
5. Rechecks the recovery session before commit.

If preserving originals or writing the replacement fails, the entire transaction rolls back. A successful recovery preserves local account IDs, names, password/recovery verifiers and roles, ends the recovery session, and requires normal login. It does not fabricate a restorable undo point from invalid data. The incoming backup's audit history is kept; unreadable prior audit content is preserved as raw originals instead of being silently merged or discarded.

This workflow handles application-state failures such as invalid JSON, missing state entries and missing/invalid chunks when SQLite can still read accounts and copy/write its tables. It does not repair an unreadable SQLite file, damaged table structure or a failing storage device. Those failures retain the database and the retry/help screen. No automatic reset, uninstall, deletion of the database, or cloud service is involved.

## Recovery records and original export

Administrators can open **数据管理 → 异常恢复记录**, view recovery time, actor, source filename, recovered record count, original content size and recovery ID, then export the preserved content. Other roles cannot read this history or export originals.

Original exports are LSR diagnostic files, distinct from LSB/JSON business backups. They preserve stored values as bytes, including embedded NUL and invalid UTF-8. SQLite reads each value as bounded BLOB slices; no large raw cell is returned through one Android cursor row. Preparation has progress/cancellation. Native saving uses the existing streaming copy and destination readback checksum. Completion is recorded under the initiating actor after locking and includes the recovery ID. Original exports never replace the last successful business-backup receipt.

LSR files are unencrypted and exclude the separate account table and credential verifiers. They can contain the complete previous business data and settings. They cannot be imported through the business-restore page. Preserved originals remain app-private until explicitly exported, are not included in regular LSB/JSON backups, and are lost on uninstall/clearing app data. No automatic retention deletion is performed. Recovery needs enough free space for preserved originals and replacement data; insufficient space causes rollback. The 256 MiB export-file limit includes base64 expansion, so it is smaller than 256 MiB of raw source content.

## LSR 1 format

UTF-8, LF-delimited records:

- First line: `LINESIGHT-RECOVERY/1`.
- `manifest`: the immutable recovery metadata under `snapshot`.
- For each raw cell, a `cell` line identifies `table` (`state` or `chunks`), `key` or `owner`/`part`, and the raw byte count.
- Consecutive `segment` lines contain a zero-based `index` and `base64` bytes, at most 64 KiB of source bytes per segment. Concatenation reconstructs the exact stored value; it does not normalize invalid text.
- `endCell` records the segment count, including zero for empty values.
- Final `checksum` line records `SHA-256`, payload byte count and payload digest. The payload includes every preceding byte and LF. The checksum line also ends in LF.

SQL table names and output line framing are fixed by the app. State keys are JSON values, never filenames or executable statements. The native saved-file digest covers the complete file including its checksum footer. The checksum is an integrity check, not an authenticity signature.

For offline inspection on a computer, run `python tool/read_recovery_archive.py original.lsr`. Add `--extract NEW_DIRECTORY` to obtain exact raw `.bin` cell values and an `index.json` mapping each generated filename to its table/key and SHA-256. The reader checks the full payload, segment order, declared lengths, final newline and EOF before exposing a final extraction directory. It refuses existing output directories, uses generated filenames for untrusted keys, and never opens or modifies the app's database.

## Verification and installable packages

The final host suite passed 33 tests; the offline LSR reader passed 4 tests. Android coverage includes 6 recovery/authentication/data-management/large-database regression tests, 2 timezone tests and the actual native recovery/lock/save/readback/open/cancel journey. Final static analysis reported no issues. ARM64 and x64 normal-entrypoint release packages were built and hash-checked; the x64 release was installed and cold-launched into administrator setup with the visible 1.1.5 label.

Packages are retained under `build/releases/1.1.5/`, with earlier releases preserved. Android API 24 or newer, target API 36, development signing, no Internet permission. Exact checksums, test logs and compatibility limits are recorded in [LOCAL_WORKSPACE.md](LOCAL_WORKSPACE.md). [Recovery gallery](../screenshots/v1.1.5/README.md) · [Six-screen overview](../screenshots/v1.1.5/overview.jpg).
