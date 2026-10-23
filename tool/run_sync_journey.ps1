param([string]$Device = 'emulator-5554')
$ErrorActionPreference = 'Stop'
$env:LINESIGHT_SCREENSHOT_DIR = 'docs/product/linesight/acceptance/sync-batch/png'
# Explicitly retain the installed app and its data after Flutter drive finishes.
& 'C:\Users\29668\flutter\bin\flutter.bat' drive --no-pub --keep-app-running --driver test_driver/screenshots.dart --target integration_test/cloud_sync_journey_test.dart --use-application-binary build/app/outputs/apk/debug/app-debug.apk -d $Device
if ($LASTEXITCODE -ne 0) { throw 'Android sync journey failed; installed app retained' }
