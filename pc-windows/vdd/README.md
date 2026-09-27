# Écran virtuel (Virtual Display Driver) — PC-RTX5080

Installé le 2026-09-19 : [VirtualDrivers/Virtual-Display-Driver](https://github.com/VirtualDrivers/Virtual-Display-Driver) release **25.7.23**
(`VDD.Control.25.7.23.zip`, application *Virtual Driver Control* et pilote **signés** — Secure Boot actif, pas de mode test),
dossier `C:\VirtualDisplayDriver\`. Rôle : Sunshine capture cet écran (`output_name = {CHANGEME_guid…}` = `\\.\DISPLAY8`,
« VDD by MTT ») à la résolution/cadence **du client** (`dd_resolution_option = auto`, `dd_refresh_rate_option = auto`),
le Dell U4025QW étant désactivé pendant le flux (`dd_configuration_option = ensure_only_display`) et rétabli après.
Le streaming ne dépend donc plus du moniteur physique (il peut être éteint) ni de ses modes (le Dell refusait le 2560x1440 :
décrochage DisplayPort le 19/09, voir INCIDENTS.md du dépôt).

`vdd_settings.xml` (copie ici) : modes 800x600 → 3840x2160 avec cadences globales 60/90/120/144/165/244 Hz ;
`<gpu><friendlyname>NVIDIA GeForce RTX 5080</friendlyname>` (sinon le pilote se rabat sur l'iGPU AMD et la capture
traverse deux GPU). Après modification : `pnputil /restart-device "ROOT\DISPLAY\0000"`.

Mesure avec l'écran virtuel (flux 2560x1440@120, Dell éteint) : capture 2560x1440 @ 120 Hz, décodage Beelink 0,5 ms,
0 % de pertes. Cycle complet PC éteint → tuile Steam → Big Picture : 206 s (prise → Debian 55 s → Windows + Sunshine 135 s).
