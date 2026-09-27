# Installe display-auto.ps1 + tâche planifiée « display-auto » (ouverture de session de tout utilisateur + déverrouillage).
$dir = 'C:\ProgramData\display-auto'; New-Item -ItemType Directory -Force $dir | Out-Null
Copy-Item "$env:USERPROFILE\display-auto.ps1" "$dir\display-auto.ps1" -Force
$a  = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $dir\display-auto.ps1 auto"
$logon = New-ScheduledTaskTrigger -AtLogOn
$cls = Get-CimClass -Namespace Root/Microsoft/Windows/TaskScheduler -ClassName MSFT_TaskSessionStateChangeTrigger
$unlock = New-CimInstance -CimClass $cls -ClientOnly -Property @{ StateChange = 8; Enabled = $true }   # 8 = SessionUnlock
$pr = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited                        # BUILTIN\Users, session interactive
$st = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName display-auto -Action $a -Trigger $logon,$unlock -Principal $pr -Settings $st -Force | Out-Null
Get-ScheduledTask display-auto | ft TaskName,State -auto
