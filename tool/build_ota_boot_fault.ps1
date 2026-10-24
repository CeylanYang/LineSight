param(
    [ValidatePattern('^ota[0-9]+-fault$')][string]$EvidenceBatch = 'ota67-fault',
    [ValidateSet('production','preview')][string]$Track = 'production'
)
$ErrorActionPreference = 'Stop'
# Reuse release signing and audit guards, but keep the intentionally faulty APK
# outside all normal delivery/OTA staging paths. Do not publish this artifact.
$taskScript = Get-Content tool/build_signed_delivery.ps1 -Raw
if (-not $taskScript.Contains('lib/main.dart') -or -not $taskScript.Contains("'.artifact-work/release'")) {
    throw 'Delivery builder changed; review isolated fault builder'
}
$taskScript = $taskScript.Replace('lib/main.dart', 'tool/fixtures/ota_boot_fault.dart')
$taskScript = $taskScript.Replace("'.artifact-work/release'", "'.artifact-work/$EvidenceBatch'")
$taskGenerated = Join-Path (Get-Location) ".artifact-work/build-$EvidenceBatch.ps1"
[IO.File]::WriteAllText($taskGenerated, $taskScript)
& $taskGenerated -Track $Track -OtaRevision 5 -EvidenceBatch $EvidenceBatch -WithAudit
if (-not $?) { throw 'Isolated fault build failed' }
Copy-Item -LiteralPath 'build/app/outputs/mapping/release/mapping.txt' -Destination ".artifact-work/$EvidenceBatch/mapping.txt"
