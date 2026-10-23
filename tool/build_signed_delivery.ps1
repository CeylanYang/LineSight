param(
    [ValidateSet('preview','production')][string]$Track = 'production',
    [switch]$WithAudit,
    [ValidatePattern('^[a-z0-9-]+$')][string]$EvidenceBatch = 'release'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
$taskOutput = Join-Path (Get-Location) '.artifact-work/release'
New-Item -ItemType Directory -Force -Path $taskOutput | Out-Null
$taskVersionMatch = [regex]::Match((Get-Content pubspec.yaml -Raw), '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$')
if (-not $taskVersionMatch.Success) { throw 'Expected a semantic version plus numeric Android build number in pubspec.yaml' }
$taskVersion = $taskVersionMatch.Groups[1].Value
$taskBuildNumber = $taskVersionMatch.Groups[2].Value
$ErrorActionPreference = 'Continue'
& 'C:\Users\29668\flutter\bin\flutter.bat' build apk --release --config-only --no-pub --target lib/main.dart --target-platform android-arm64,android-x64 --build-number $taskBuildNumber --dart-define-from-file=.artifact-work/sso/demo-build.json *> ".artifact-work/sso/$EvidenceBatch-$Track-config.log"
$configurationExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($configurationExitCode -ne 0) { throw 'Flutter release configuration failed' }
$registrant = 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$registration = Get-Content $registrant -Raw
$registration = [regex]::Replace($registration, '(?s)    try \{\s*flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\s*\} catch \(Exception e\) \{\s*Log\.e\(TAG, "Error registering plugin integration_test,[^\r\n]*\r?\n    \}\r?\n', '')
[IO.File]::WriteAllText((Join-Path (Get-Location) $registrant), $registration, [Text.UTF8Encoding]::new($false))
$cloudConfig = Get-Content .artifact-work/sso/demo-build.json -Raw | ConvertFrom-Json
$cloudDefines = ($cloudConfig.PSObject.Properties | ForEach-Object { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($_.Name + '=' + $_.Value)) }) -join ','
$gradleArguments = @('-p','android','-I','../tool/gradle_mirrors.init.gradle','-Dhttp.proxyHost=','-Dhttps.proxyHost=','-Ptarget-platform=android-arm64,android-x64','-Ptarget=lib/main.dart',"-Pdart-defines=$cloudDefines",'--no-daemon','--max-workers=2')
if ($Track -eq 'preview') { $gradleArguments += '-PlinesightPreviewSigning=true' }
$gradleArguments += 'assembleRelease'
if ($WithAudit) { $gradleArguments += 'assembleReleaseAndroidTest' }
$ErrorActionPreference = 'Continue'
& .\android\gradlew.bat @gradleArguments *> ".artifact-work/sso/$EvidenceBatch-$Track-build.log"
$buildExitCode = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($buildExitCode -ne 0) { throw "Release build failed for $Track" }
$apk = Join-Path (Get-Location) 'build/app/outputs/apk/release/app-release.apk'
$archive = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    foreach ($entry in $archive.Entries | Where-Object { $_.FullName -match '\.dex$' }) {
        $stream = $entry.Open(); $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            $dex = [Text.Encoding]::ASCII.GetString($buffer.ToArray())
            if ($dex.Contains('IntegrationTestPlugin') -or $dex.Contains('StorageAuditInstrumentation')) { throw 'Acceptance code unexpectedly packaged in app DEX' }
        } finally { $stream.Dispose(); $buffer.Dispose() }
    }
} finally { $archive.Dispose() }
$buildTools = 'C:\Users\29668\AppData\Local\Android\Sdk\build-tools\36.1.0'
& "$buildTools\apksigner.bat" verify --verbose --print-certs $apk *> ".artifact-work/sso/$EvidenceBatch-$Track-signature.log"
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed' }
$certificate = [regex]::Match((Get-Content ".artifact-work/sso/$EvidenceBatch-$Track-signature.log" -Raw), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)').Groups[1].Value.ToLowerInvariant()
if ($Track -eq 'production') {
    $expected = (Get-Content docs/product/linesight/acceptance/release-batch/release-certificate.json -Raw | ConvertFrom-Json).certificate_sha256
    if ($certificate -ne $expected) { throw 'APK does not use the private production certificate' }
}
$stagedApk = Join-Path $taskOutput "LineSight-$taskVersion-$taskBuildNumber-$Track.apk"
Copy-Item -LiteralPath $apk -Destination $stagedApk -Force
if ($WithAudit) {
    $audit = Join-Path (Get-Location) 'build/app/outputs/apk/androidTest/release/app-release-androidTest.apk'
    if (-not (Test-Path -LiteralPath $audit)) { throw 'Native audit APK missing' }
    & "$buildTools\apksigner.bat" verify --print-certs $audit *> ".artifact-work/sso/$EvidenceBatch-$Track-audit-signature.log"
    if ($LASTEXITCODE -ne 0) { throw 'Audit APK signature invalid' }
    $auditCertificate = [regex]::Match((Get-Content ".artifact-work/sso/$EvidenceBatch-$Track-audit-signature.log" -Raw), 'Signer #1 certificate SHA-256 digest: ([0-9a-fA-F]+)').Groups[1].Value.ToLowerInvariant()
    if ($auditCertificate -ne $certificate) { throw 'Audit APK certificate differs from target' }
    Copy-Item -LiteralPath $audit -Destination (Join-Path $taskOutput "LineSight-storage-audit-$Track.apk") -Force
}
$badging = & "$buildTools\aapt.exe" dump badging $stagedApk
if ($LASTEXITCODE -ne 0 -or ($badging -match 'application-debuggable')) { throw 'Customer APK must be a non-debuggable release' }
$badging | Select-Object -First 2
Write-Output "Verified $Track APK; certificate SHA-256 $certificate"
