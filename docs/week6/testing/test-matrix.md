# Self-test plan and result ledger

Internal self-testing covered the integrated team workflow before external user testing.

| ID | Area | Scenario | Result/evidence |
|---|---|---|---|
| T01 | Startup | Install and launch on Android API 36 x86_64 | PASS — bright local sign-in loaded; `android-cloud-final.png` |
| T02 | Team workspace | Connect to deployed HTTPS service, create team account and workspace | PASS — owner role was shown during the live check; temporary verification data removed. `android-cloud-team-login.png` records the service connection screen. |
| T03 | Task workflow | Create task, move through printing and inspection | PASS — task state and actions shown in `android-team-inspection.png` |
| T04 | Image evidence | Upload PNG and open original/edge reference preview | PASS — `android-team-image-review.png`; original and edge reference loaded |
| T05 | Inspection closure | Pass inspection and close task | PASS — `android-team-final.png` |
| T06 | Exception handling | Record exception, process it, then close task | PASS — completed during manual Android journey; state persisted |
| T07 | Persistence | Restart app and verify saved team task | PASS — closed task remained visible after relaunch |
| T08 | Legacy import | Preview import of existing local inspection records | PASS — preview count and import action checked |
| T09 | API authorization | Invite replay, role restriction, and workspace isolation | PASS — collaboration API suite and remote HTTPS smoke workflow |
| T10 | Localization and visual style | Review bright interface, roles, inspection time, and photo action in Chinese | PASS — product labels and roles are Chinese; timestamps use device-local format. User-entered names and printer/source identifiers retain their entered/original form |
| T11 | Network retry | Interrupt upload and retry without duplication | NOT VERIFIED |
| T12 | Deployment | HTTPS, tenant isolation, backup/restore, rollback | PARTIAL — HTTPS API/Admin deployed and mobile account/workspace creation verified; backups/restore drills and rollback rehearsal remain unverified |
| T13 | Admin UI | Open live Django admin sign-in page | PASS — remote HTTPS Admin page and static CSS returned HTTP 200; administrator login was verified |
| T14 | Ready-to-use demo | Sign in with pre-created team account and load seeded workspace | PASS — Android API 36 loaded `LineSight 演示组`, all four member roles, and seeded task states; `android-demo-workspace.png`, `android-demo-tasks.png` |
| T15 | Demo permissions and evidence | Check read-only access and retrieve seeded image/edge reference | PASS — viewer write request returned HTTP 403; stored evidence preview returned HTTP 200 as PNG |
| T16 | Packaged service default | Cold-start APK and sign in while leaving the service URL field blank | PASS — the APK used its built-in HTTPS base URL and loaded the viewer workspace; `android-demo-viewer.png` |

## Automated results

- `flutter analyze --no-pub` — PASS, no issues.
- `flutter test --no-pub` — PASS, all 89 tests.
- Django system checks including Admin — PASS.
- Local collaboration API tests — PASS, 10 tests (workspace access, invitation replay, role restrictions, image validation, idempotency, exception resolution, and other collaboration APIs).
- Final Android debug APK: 1.1.18+4022, installed and launched on Android API 36 emulator; remote collaboration endpoint is built in.
- Delivered APK metadata and SHA-256: `06_delivery/build-artifact.md`.

## Manual run record

2026-10-21; Android API 36 x86_64 emulator; app build 1.1.18+4022. Signed into the deployed HTTPS API with a pre-created team owner account, opened `LineSight 演示组`, and verified its four members and prepared records on-device. The API checks confirmed all four accounts can sign in, the viewer is read-only, and the seeded image preview is served over HTTPS. The earlier Android workflow covered task status progression, image upload and original/edge preview, inspection closure, exception handling, persistence after restart, and legacy import preview. Screenshots are indexed in `04_screenshots/README.md`.

## Scope notes

The collaboration service runs remotely over HTTPS with a separate persistent SQLite database and media directory. The Android app's remote account/workspace creation has been verified. Network interruption/retry, cloud backup/restore, and rollback remain unverified. External user testing has not started.
