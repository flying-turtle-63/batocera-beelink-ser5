# Installe steam-guard.ps1 + tâche « steam-guard » (ouverture de session de `batocera`), depuis une session admin SSH.
$dir = 'C:\ProgramData\display-auto'; New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item "$env:USERPROFILE\steam-guard.ps1" "$dir\steam-guard.ps1" -Force
$a  = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $dir\steam-guard.ps1"
$t  = New-ScheduledTaskTrigger -AtLogOn -User batocera
$pr = New-ScheduledTaskPrincipal -UserId batocera -LogonType Interactive
$st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName steam-guard -Action $a -Trigger $t -Principal $pr -Settings $st -Force | Out-Null
Get-ScheduledTask steam-guard | ft TaskName,State -auto
