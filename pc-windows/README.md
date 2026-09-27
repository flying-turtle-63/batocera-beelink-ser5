# PC Windows — Sunshine (streaming vers le Beelink Batocera)

> English version: [README.en.md](README.en.md).

PC dual-boot : la partition Windows sert de cible de streaming Moonlight/Sunshine pour le Beelink (`../README.md`, sections « Streaming », « éléments dimensionnants » et « réveil du PC »). La partition Linux du même PC physique (`pc`, `CHANGEME_ip`, le PC de jeu) est documentée dans le dépôt homelab, pas ici.

## Matériel et rôle dans la chaîne

| | |
|---|---|
| Machine | le PC de jeu, hostname Windows `CHANGEME_hostname`, IP `CHANGEME_pc_ip` (réservation DHCP, différente du `.14` Linux) |
| CPU / GPU / RAM | Ryzen 7 9800X3D, **RTX 5080**, 96 Go |
| Encodeur | NVENC HEVC, preset P1, sans two-pass : 1,5 ms à 1080p120, 3,5 ms (max 6,5) à 2880×1620@120 — jamais limitant |
| Sunshine | 2026.914, **service Windows** `SunshineService` (démarrage automatique) |
| Écran capturé | **Écran virtuel** Virtual Display Driver 25.7.23 (`vdd/`), 120 Hz, modes jusqu'à 4K120 dont 2880×1620 ajouté à la main ; le Dell U4025QW (5120×2160@120) est désactivé pendant le flux |
| Session | compte standard dédié **`batocera`**, Autologon Sysinternals, Steam au démarrage |
| Alimentation | prise Zigbee coupée par Home Assistant quand le PC est éteint ; réveil piloté depuis le Beelink via le N100 (`../tools/pc-wake.sh`) |

Le PC ne limite rien dans la chaîne : la résolution du flux est bornée par la sortie HDMI 2.0 et le décodeur du Beelink (voir `../README.md`). Ce qui borne côté PC, c'est le jeu lui-même (cadence, Reflex).

## Service Sunshine

Sunshine **doit tourner en tant que service Windows**, pas en tâche planifiée :

- Une instance lancée par le Planificateur de tâches ne peut créer aucun processus enfant → **erreur 5 (accès refusé)** dès qu'elle tente de lancer une app (Steam, etc.).
- Lancé manuellement sans élévation, Sunshine plante à l'ouverture d'une application.
- La tâche planifiée historique **« Sunshine (session) » est laissée DÉSACTIVÉE** — conservée pour référence mais ne doit pas être réactivée. Le service Windows « Sunshine Service » est la seule source de vérité.
- L'injection des entrées (manette) peut cesser silencieusement après un redémarrage du service pendant un flux actif : redémarrer à froid, sans flux ouvert.

## Session Windows et Steam

- Session dédiée **`batocera`** (compte standard) ouverte automatiquement au démarrage (Autologon Sysinternals) ; le compte `<utilisateur>` n'est plus ouvert automatiquement. Tant qu'aucune session n'est ouverte, Sunshine diffuse du **noir à ~21 fps** : premier réflexe quand l'image est noire.
- Steam démarre avec la session et reste connecté : **un seul compte Steam mémorisé** sur la machine (sinon le sélecteur « Qui joue ? » bloque).
- Première ouverture d'un compte standard : lancer `SteamService.exe /repair` depuis une session admin (sinon la boîte « Erreur du service Steam » bloque Big Picture) ; l'installateur StartAllBack se présente une fois pour le nouveau profil.
- Application Sunshine « Steam Big Picture » (`sunshine/apps.json`) :
  - commande (`cmd`) **vide**, lancement réel via `detached` : `cmd /C start "" steam://open/bigpicture` ;
  - `prep-cmd` **do** : `cmd /C "shutdown /a … & exit /b 0"` (annule une extinction différée en cours), **undo** : `steam://close/bigpicture` puis `shutdown /s /t 900` (le PC s'éteint 15 min après la fin du flux ; HASS coupe ensuite la prise) ;
  - **non élevée** (`elevated: false`) — une élévation UAC bloquerait le lancement piloté par Sunshine ;
  - la tuile se termine immédiatement côté Beelink si la session est verrouillée (aucun processus à attendre).
- Incident vu au boot à froid du 20/09 : Steam n'a démarré ni par sa clé Run ni par `steam://` (exit 5, pas de `bootstrap_log.txt`) jusqu'à un lancement manuel ; suspect = redémarrage du pilote VDD pendant l'ouverture de session. À surveiller.

## Configuration Sunshine (`sunshine/sunshine.conf`)

- `output_name = CHANGEME_guid_de_l_ecran_virtuel` — l'écran virtuel (`\\.\DISPLAY8`), pas le Dell.
- `dd_configuration_option = ensure_only_display`, `dd_resolution_option = auto`, `dd_refresh_rate_option = auto` — le VDD prend la résolution et la cadence du client (2880×1620@120, 3840×2160@60…), le Dell est coupé pendant le flux. **Ces réglages `auto` ne sont sûrs qu'avec l'écran virtuel** : avec le Dell comme sortie, un client 1440p avait fait décrocher le moniteur du DisplayPort et laissé Windows sans écran (`WinDisc 1024×768`, « Topology input is empty ») — tous les flux noirs jusqu'au rallumage physique. Sans VDD, imposer `dd_resolution_option = manual` + `dd_manual_resolution = 3840x2160`.
- `nvenc_preset = 1`, `nvenc_twopass = disabled`, `nvenc_vbv_increase = 100`, `nvenc_spatial_aq = enabled` — latence d'encodage minimale ; à 120 Mbit/s le P4 + two-pass n'apportait rien de visible.
- `csrf_allowed_origins` = origine(s) de l'interface web, liste séparée par des **virgules, sans crochets** (une syntaxe avec crochets est silencieusement invalide) — à mettre à jour si l'IP change.
- `gamepad_driver = all` — nécessite **ViGEmBus** installé pour émuler les manettes côté client.
- `locale = fr`.

Non versionnés (secrets) : `sunshine_state.json` (état/pairing), certificats Sunshine.

## Écran virtuel

Voir [vdd/README.md](vdd/README.md) : installation du Virtual Display Driver (signé, `C:\VirtualDisplayDriver`, lié au GPU NVIDIA), `vdd_settings.xml` avec la liste globale des cadences (dont 120) et l'entrée 2880×1620. Pour un nouveau profil de flux côté Beelink, ajouter d'abord le mode ici, sinon Sunshine retombe sur le mode le plus proche.

## Écran au démarrage (`display-auto/`)

Windows mémorise une topologie par combinaison d'écrans branchés. Si un flux se termine mal (PC éteint en plein flux, donc sans restauration par Sunshine), la combinaison {Dell + VDD} reste enregistrée en « VDD seul » : au boot suivant, **aucune image sur le Dell** alors qu'il est branché (constaté le 23/09).

`display-auto.ps1` (installé dans `C:\ProgramData\display-auto\` par `install-display-auto.ps1`, depuis une session admin SSH) tourne via la tâche planifiée **`display-auto`** à l'ouverture de session de n'importe quel utilisateur et au déverrouillage. Si le Dell (`DEL430F`) est présent sur la RTX, il devient l'écran **seul** actif (mode repris de la base Windows, 5120×2160@120). Sinon, il ne fait rien : le VDD est alors le seul écran et Windows l'active de lui-même. Pendant un flux (ports UDP 47998-48000 ouverts), il ne touche à rien : c'est Sunshine (`ensure_only_display`) qui bascule sur le VDD et restaure ensuite. Journal : `C:\ProgramData\display-auto\display-auto.log`. `display-auto.ps1 status` liste les écrans disponibles et actifs, mais seulement depuis la session console (tâche `/it`), pas depuis la session 0 de SSH.

### Filet Steam (`steam-guard/`)

La tâche **`steam-guard`** (ouverture de session de `batocera`) vérifie 60 s après le logon que Steam tourne. Sinon, elle relance le raccourci *Démarrage* via `explorer.exe` (3 essais espacés de 45 s). Journal : `C:\ProgramData\display-auto\steam-guard.log`.

## Réseau

- **UPnP désactivé** sur le routeur pour Sunshine — pas d'exposition automatique de port hors LAN, le flux reste confiné au réseau local (`<votre sous-réseau>/24`).
- Ethernet Gigabit ; le flux à 120 Mbit/s en utilise 12 %, 0 % de pertes mesurées.

## Accès SSH

- `ssh pc-win` → `<utilisateur>@CHANGEME_pc_ip`, OpenSSH Server (fonctionnalité Windows), clé `~/.ssh/pc_windows` autorisée via `administrators_authorized_keys` (compte administrateur local, pas `authorized_keys` utilisateur standard). L'alias historique `pcwin` (`.125`) est périmé.
- Lire un fichier : `ssh pc-win type "C:\chemin\vers\fichier"`.
- Exécuter un script PowerShell : `scp` du script vers le PC puis `ssh pc-win powershell -NoProfile -ExecutionPolicy Bypass -File "C:\chemin\script.ps1"`.
- Tout ce qui doit toucher le bureau (lancer Chrome, Steam, testufo…) passe par une tâche planifiée `schtasks /it` : la session 0 de SSH n'atteint pas le bureau.

## Diagnostic d'un flux noir ou lent

Dans l'ordre, **avant** d'accuser le Beelink : (1) session Windows ouverte ? (2) `Get-PnpDevice -Class Monitor` : l'écran virtuel est-il `OK` ? Écran du bureau noir au boot : voir `display-auto.log`. (3) journal Sunshine : erreurs de topologie ? (4) `Get-Process steam`. Côté Beelink : overlay Moonlight (Hotkey+Y) et `../tools/mltest.sh`.

## Depuis le Beelink

Quitter un flux Moonlight en cours : **Hotkey+Start** (Xbox/Guide + Start sur manette Xbox 360, evmapy) ou **Ctrl+Alt+Shift+Q** au clavier. Le raccourci Select+Start habituel de Batocera ne fonctionne pas pour sortir de Moonlight.
