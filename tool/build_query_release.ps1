param([switch]$NoInstall)
$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
& 'C:\Users\29668\flutter\bin\flutter.bat' build apk --release --config-only --target lib/main.dart --target-platform android-arm64,android-x64 --build-number 8036 --dart-define-from-file=.artifact-work/sso/demo-build.json *> .artifact-work/sso/query-release-config.log
if ($LASTEXITCODE -ne 0) { throw 'Flutter release configuration failed' }
$cloudConfig = Get-Content .artifact-work/sso/demo-build.json -Raw | ConvertFrom-Json
$cloudDefines = ($cloudConfig.PSObject.Properties | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Name + '=' + $_.Value)) }) -join ','
& .\android\gradlew.bat -p android -I ../tool/gradle_mirrors.init.gradle '-Dhttp.proxyHost=' '-Dhttps.proxyHost=' '-Ptarget-platform=android-arm64,android-x64' '-Ptarget=lib/main.dart' "-Pdart-defines=$cloudDefines" assembleRelease *> .artifact-work/sso/query-release-build.log
if ($LASTEXITCODE -ne 0) { throw 'Release build failed' }
if (Select-String android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java -Pattern 'IntegrationTest' -Quiet) { throw 'Unexpected integration-test registration' }
& 'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.1.0\aapt.exe' dump badging build/app/outputs/apk/release/app-release.apk | Select-Object -First 2
& 'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.1.0\apksigner.bat' verify build/app/outputs/apk/release/app-release.apk
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
if (-not $NoInstall) {
    & 'C:\Users\29668\AppData\Local\Android\Sdk\platform-tools\adb.exe' install -r build/app/outputs/apk/release/app-release.apk
}

