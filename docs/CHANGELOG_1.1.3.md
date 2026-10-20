# LineSight 1.1.3 — portable timestamps and local calendar dates

## Changed

- Inspection/review times, audit events, restore-point creation and local backup receipts serialize as UTC ISO 8601 with `Z`. CSV headings explicitly state UTC. Schema remains 1.
- Lists display device-local time. Record/audit details, backup metadata and restore comparisons include the UTC offset applying at that instant.
- Dashboard dates, inclusive record filters, audit date ranges and chart buckets use local calendar boundaries. Day navigation uses calendar construction instead of adding or subtracting 24 hours.
- Restore comparisons treat different offsets describing the same instant as equal.
- Strict parsing rejects nonexistent calendar dates, malformed or out-of-range offsets and precision beyond microseconds, avoiding silent normalization/truncation.

- Login, settings and help now share one version label, checked against the package version.

## Importing older backups

The original source of a timestamp without a timezone cannot be inferred. Import retains the input text until the preview closes. Before comparison and restore, choose device historical timezone rules or a fixed UTC offset. The UI shows an original clock-time example alongside its interpreted local time, then requires acknowledgement. Changing the choice always reinterprets the original strings. Timestamps already containing an offset stay at the same instant.

The restore audit records the chosen rule and legacy-field count. A fixed offset applies to all naive timestamps; it does not implement a region's summer/winter transitions. Use a device set to the source region for historical rules. Repeated clock times at the end of daylight saving remain ambiguous without additional evidence. A skipped local clock time is rejected in an imported backup when using local rules; a known fixed offset may be selected instead.

## Existing local databases

At upgrade, naive timestamps retain the previous interpretation using the upgrading device's historical local rules. The original workspace, prior undo snapshot and point/receipt metadata strings are preserved in a separate local archive in the same SQLite transaction that writes the normalized timestamps. A failed transaction preserves the prior database without a partial archive. Restarting a successfully upgraded database does not repeat this conversion.

The **数据管理 → 时间与日期** screen explains the assumption and lists each retained archive. Engineers and administrators can export the original workspace or prior undo snapshot as an importable schema-1 JSON file and choose a corrected source rule. The archive survives normal restore/undo; a later upgrade from downgraded software appends another archive instead of overwriting the first. Archives contain no account credentials and are not included in normal business backups.

For local database compatibility, a skipped historical clock time follows the platform's existing adjustment behavior. The raw value remains available in the archive. Current-offset metadata describes the upgrade moment, not a fixed offset applied to historical data.

Recovering from an incorrectly assumed old timezone restores an upgrade-time snapshot: export current data first and inspect changes. Existing same-ID audit events are retained under the established audit-merge policy. Old exports are still bounded by 20 MB; local originals remain preserved if they exceed that limit.

## Evidence

See [LOCAL_WORKSPACE.md](LOCAL_WORKSPACE.md) for final run results and package hashes. Test sources include `test/time_test.dart`, expanded narrow/large-text detail layouts and `integration_test/time_portability_test.dart`. The Android time test requires a disposable emulator set to `America/New_York`; restore its previous timezone after the run.
