param()
$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
& 'C:\Users\29668\flutter\bin\flutter.bat' build apk --release --config-only --no-pub --target lib/main.dart --target-platform android-arm64,android-x64 --build-number 8050 --dart-define-from-file=.artifact-work/sso/demo-build.json *> .artifact-work/sso/vision-release-config.log
if ($LASTEXITCODE -ne 0) { throw 'Flutter release configuration failed' }
# A preceding Flutter test can leave its development-only plugin registered.
# This generated Java file must match the normal release entry point.
$registrant = 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$registration = Get-Content $registrant -Raw
$registration = [regex]::Replace($registration, '(?s)    try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{\s*Log\.e\(TAG, "Error registering plugin integration_test,[^\r\n]*\r?\n    \}\r?\n', '')
[IO.File]::WriteAllText((Join-Path (Get-Location) $registrant), $registration, [Text.UTF8Encoding]::new($false))
$cloudConfig = Get-Content .artifact-work/sso/demo-build.json -Raw | ConvertFrom-Json
$cloudDefines = ($cloudConfig.PSObject.Properties | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Name + '=' + $_.Value)) }) -join ','
$ErrorActionPreference = 'Continue' # Windows PowerShell wraps native stderr warnings as ErrorRecords.
& .\android\gradlew.bat -p android -I ../tool/gradle_mirrors.init.gradle '-Dhttp.proxyHost=' '-Dhttps.proxyHost=' '-Ptarget-platform=android-arm64,android-x64' '-Ptarget=lib/main.dart' "-Pdart-defines=$cloudDefines" --no-daemon --max-workers=2 assembleRelease *> .artifact-work/sso/vision-release-build.log
$buildExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($buildExitCode -ne 0) { throw 'Release build failed' }
$archive = [IO.Compression.ZipFile]::OpenRead((Join-Path (Get-Location) 'build/app/outputs/apk/release/app-release.apk'))
try {
    foreach ($entry in $archive.Entries | Where-Object { $_.FullName -match '\.dex$' }) {
        $stream = $entry.Open()
        $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            if ([Text.Encoding]::ASCII.GetString($buffer.ToArray()).Contains('IntegrationTestPlugin')) { throw 'Unexpected integration-test plugin in APK' }
        } finally { $stream.Dispose(); $buffer.Dispose() }
    }
} finally { $archive.Dispose() }
& 'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.1.0\aapt.exe' dump badging build/app/outputs/apk/release/app-release.apk | Select-Object -First 2
& 'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.1.0\apksigner.bat' verify build/app/outputs/apk/release/app-release.apk
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
