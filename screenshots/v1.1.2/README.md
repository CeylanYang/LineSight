# LineSight 1.1.2 — data management and traceability

Actual Android emulator captures from `integration_test/restore_journey_test.dart` using a disposable local workspace with marked example inspections.

| Screen | Capture |
|---|---|
| Data management and local backup status | [data-management.png](data-management.png) |
| Backup metadata and restore impact | [restore-preview.png](restore-preview.png) |
| Searchable record change list | [restore-record-list.png](restore-record-list.png) |
| Current and restored field values | [restore-record-detail.png](restore-record-detail.png) |
| Local restore point preview | [restore-point.png](restore-point.png) |
| Record-linked operation history | [record-audit.png](record-audit.png) |
| Audit event with before/after values | [audit-detail.png](audit-detail.png) |
| Dark audit detail | [audit-detail-dark.png](audit-detail-dark.png) |
| Normal release APK cold launch | [release-onboarding.png](release-onboarding.png) |

The preview fixture contains 97 current records and a 96-record backup, with one reviewed/archived record changed and one later simulation absent from the backup. The journey restores that backup, then uses the saved local point to return to the 97-record workspace. Account credentials and recovery codes are not shown.

Run the capture driver with `LINESIGHT_SCREENSHOT_DIR=screenshots/v1.1.2`, then run `python tool/make_preview.py --version v1.1.2` for the [overview](overview.jpg).
