$ErrorActionPreference = 'Stop'
# Reuse release signing and audit guards, but keep the intentionally faulty APK
# outside all normal delivery/OTA staging paths. Do not publish this artifact.
$taskScript = Get-Content tool/build_signed_delivery.ps1 -Raw
if (-not $taskScript.Contains('lib/main.dart') -or -not $taskScript.Contains("'.artifact-work/release'")) {
    throw 'Delivery builder changed; review isolated fault builder'
}
$taskScript = $taskScript.Replace('lib/main.dart', 'tool/fixtures/ota_boot_fault.dart')
$taskScript = $taskScript.Replace("'.artifact-work/release'", "'.artifact-work/ota67-fault'")
$taskGenerated = Join-Path (Get-Location) '.artifact-work/build-ota67-fault.ps1'
[IO.File]::WriteAllText($taskGenerated, $taskScript)
& $taskGenerated -Track production -OtaRevision 5 -EvidenceBatch ota67-fault -WithAudit
