$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$python = Join-Path (Split-Path -Parent $repo) 'week6-cloud\.venv-backend\Scripts\python.exe'
if (!(Test-Path -LiteralPath $python)) { throw 'Backup Python environment is missing.' }
$script = Join-Path $PSScriptRoot 'offhost_backup.py'
$action = New-ScheduledTaskAction -Execute $python -Argument ('"' + $script + '"') -WorkingDirectory $repo
$triggers = @((New-ScheduledTaskTrigger -Daily -At '04:15'), (New-ScheduledTaskTrigger -AtLogOn -User ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)))
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 15) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'LineSight-Encrypted-Offhost-Backup' -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description 'Pull and verify encrypted LineSight cloud snapshots while the development user is logged in. No passwords stored in this task.' -Force | Out-Null
Get-ScheduledTask -TaskName 'LineSight-Encrypted-Offhost-Backup' | Select-Object TaskName, State
