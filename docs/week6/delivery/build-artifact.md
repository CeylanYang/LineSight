# Build artifact

- File: `LineSight-1.1.18-debug.apk`
- Size: 155534172 bytes
- SHA-256: `DA54402776DA132635DEEBA01C72461842BE8F0A5209A09229EFAA884EC2F13D`
- Version: 1.1.18+4022
- Build: Flutter 3.44.4 / Dart 3.12.2; Android API 36 emulator; debug signing
- Service endpoint: `https://47.111.81.94/api/v1/` (built in with `LINESIGHT_API_BASE_URL`)
- Install and launch: PASS — installed and launched on Android API 36 emulator.
- Remote demo check: PASS — after a cold start, signed in with the service URL field blank and the APK's built-in HTTPS address; loaded the pre-created `LineSight 演示组` and its members/tasks on Android. The server contains ready-to-use owner, operator, inspector, and read-only accounts plus tasks, an exception, a completed inspection, and image evidence.
- Automated checks: `flutter analyze --no-pub` clean; all 89 Flutter tests passed.
- This is an internally tested debug build. External user testing, backup/restore drills, rollback rehearsal, and SSH source-IP allowlisting remain follow-up work.
- Team onboarding and management handoff: `team-access-and-admin.md`.
