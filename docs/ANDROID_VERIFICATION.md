# Android verification without driver cleanup uninstall

Use the disposable emulator for device tests. Suites use unique database paths,
but Flutter's device runner controls the entire installed package. In this
workstation's Flutter 3.44.4, `flutter drive` uninstalls the package at completion
unless `--keep-app-running` is supplied. A lower test version code can also cause
a failed install followed by uninstall/reinstall. Both occurred during earlier
development; their observations remain in the archived reports.

## Current release: 1.1.9+11

The x64 release split uses version code **4011**. Build the test APK with that
code, then drive the exact binary. Commands below are PowerShell, run from the
active source directory with Flutter and adb on PATH:

```powershell
adb shell cmd package list packages -U com.example.linesight_flutter
adb shell dumpsys package com.example.linesight_flutter
adb shell am force-stop com.example.linesight_flutter
flutter build apk --debug --target integration_test/storage_regression_test.dart --target-platform android-x64 --build-number 4011
flutter drive --debug --driver test_driver/screenshots.dart --target integration_test/storage_regression_test.dart --use-application-binary build/app/outputs/flutter-apk/app-debug.apk --keep-app-running -d emulator-5554
adb shell cmd package list packages -U com.example.linesight_flutter
adb shell am force-stop com.example.linesight_flutter
```

Check each exit code before continuing. The installed version code must be no
higher than the test APK code, and signatures must match. Record UID and package
installation metadata before and after each run. UID continuity is supporting
evidence of retaining the package; it is not a byte-for-byte database audit.
Never count a runner's teardown as an extra business scenario.

`dumpsys package` prints installation timestamps in the device's current local
timezone. Normalize these values to UTC using the timezone recorded with each
snapshot before comparing suites that change timezone. A four-hour text shift
between GMT and New York in October does not by itself indicate reinstallation.

Other targets:

| Target | Business scenarios | Device timezone |
|---|---:|---|
| `storage_regression_test.dart` | 7 | Original timezone |
| `release_timezone_test.dart` | 4 | `America/New_York` |
| `record_review_journey_test.dart` | 2 | Original timezone |

`release_timezone_test.dart` aggregates the two time-portability scenarios and
two query-cache scenarios. Save `adb shell getprop persist.sys.timezone`, set the
required timezone with `adb shell cmd alarm set-timezone America/New_York`, and
restore the saved value in `finally`, including on build/test failure. Never
change the host timezone. Set `LINESIGHT_SCREENSHOT_DIR` to a distinct report
directory when using the screenshot driver.

## Return to the normal app

Build release APKs from `lib/main.dart` using the default pub step after device
testing. The step regenerates the native plugin registrant; `--no-pub` can leave
the integration-test plugin registered and break release compilation.

```powershell
flutter build apk --release --target lib/main.dart --target-platform android-arm64,android-x64 --split-per-abi
adb install -r build/app/outputs/flutter-apk/app-x86_64-release.apk
```

The explicit `adb install -r` reports an installation error without a Flutter
fallback uninstall. Verify the installed APK bytes, version, signature, manifest
and UID afterward. Keep first-launch timeouts in the report even if a later
frame or another cold launch succeeds. `tool/observe_android_launch.py` preserves
these separate observations. Test databases remain inside the retained package;
the normal entrypoint opens its own workspace database.
