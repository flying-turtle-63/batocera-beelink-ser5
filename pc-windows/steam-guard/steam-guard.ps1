# steam-guard.ps1 — filet de sécurité : Steam absent après l'ouverture de session `batocera` -> relance.
# Le raccourci du dossier Démarrage échoue parfois (23/09 : après un arrêt où Steam avait refusé de se fermer).
# Lancement par explorer.exe (chemin ShellExecute) : un exec direct de steam.exe sort en code 5 dans cette session.
param([string]$Lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Steam Big Picture.lnk",
      [string]$Log = 'C:\ProgramData\display-auto\steam-guard.log')
function Say($m) { Add-Content $Log ("{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}" -f (Get-Date), $env:USERNAME, $m) }
Start-Sleep 60
for ($i = 1; $i -le 3; $i++) {
  if (Get-Process steam -ErrorAction SilentlyContinue) { if ($i -eq 1) { Say "Steam présent" } else { Say "Steam relancé (essai $($i-1))" }; return }
  Say "Steam absent, lancement $i"
  Start-Process explorer.exe -ArgumentList "`"$Lnk`""
  Start-Sleep 45
}
if (Get-Process steam -ErrorAction SilentlyContinue) { Say "Steam relancé (essai 3)" } else { Say "ÉCHEC : Steam absent après 3 essais" }
