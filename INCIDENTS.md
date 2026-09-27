# Incidents rencontrés (et résolus)

## Écran noir : EmulationStation mort, wrapper en boucle
**Symptôme** : TV noire, SSH OK. `emulationstation` absent, `emulationstation-standalone` relance ES ~6 fois par seconde (`display.log` inondé de « Top of display configuration loop »).
**Cause** : un `killall -9` de Dolphin pendant un banc automatisé a emporté ES (même signature « VK submission segfault » à chaque arrêt brutal de Dolphin).
**Résolution** : `/etc/init.d/S31emulationstation restart`. Ne jamais tuer un émulateur en `-9` ; utiliser `curl -X POST http://127.0.0.1:1234/emukill` ou la commande réseau `QUIT` de RetroArch (UDP 55355). Si deux serveurs X coexistent après un restart (`pgrep -a xinit`), faire `stop`, `killall -9 xinit X`, puis `start`.

## Machine quasi figée, arrêt des jeux interminable : driver Wi-Fi `mt7921e`
**Symptôme** : arrêts de jeu de plusieurs dizaines de secondes, émulateur bloqué sur une fenêtre blanche, SSH lent, `reboot` qui n'aboutit pas.
**Diagnostic** : `dmesg` inondé de `mt7921e: driver own failed` / `Timeout for driver own` / `chip reset failed`. Carte Wi-Fi MediaTek inutilisée (Ethernet) partie en boucle de réinitialisation ; `rmmod` et le retrait PCI se bloquent en état D et empêchent l'arrêt propre. Le thread noyau consommait un cœur entier en permanence (+7 °C en jeu).
**Résolution** : blacklist des modules `mt7921e mt7921_common mt792x_lib mt76_connac_lib mt76` (`/etc/modprobe.d/`, persisté par `batocera-save-overlay`) + service `wlan_off` de secours. Arrêt électrique nécessaire la première fois. Plan B si l'overlay empêchait le boot : supprimer `/boot/boot/overlay` depuis un PC (partition FAT).

## Plus aucun jeu ne se lance après un jeu en 120 Hz
**Symptôme** : tout lancement plante ; `es_launch_stderr.log` : `videoMode.getCurrentResolution … ValueError: invalid literal for int() with base 10: ''` ; `batocera-resolution setMode` répond « No connected output detected » alors que `xrandr --query` montre bien la sortie.
**Diagnostic** : `xrandr --listPrimary` vide — le drapeau *primary* a été perdu lors du retour 1080p120 → 4K60. `batocera-resolution` ne s'appuie que sur ce primary.
**Résolution** : `xrandr --output HDMI-1 --primary`. Le service `custom_service` le surveille désormais toutes les 5 s (sans toucher au mode vidéo) et détecte l'écran X réel (`:0` ou `:1`).

## CPU à 85–89 °C en charge, ventilateur à 1 700 tr/min
**Symptôme** : à 30 W soutenus, Tctl frôle la limite SMU (90 °C) ; la table « Fan Control » du menu SMU du BIOS n'a aucun effet.
**Diagnostic** : ventilateur piloté par le Super I/O IT8772E (`modprobe it87 ignore_resource_conflict=1`), dont l'automatique suit une thermistance de carte qui ne bouge presque pas ; à 100 % PWM le ventilo fait 5 000 tr/min.
**Résolution** : service `fanctl` (PWM manuel sur Tctl, paliers, hystérésis, retour auto à l'arrêt). Burn 30 W : 83–88 °C → 70 °C.

## Base TDP faussée après un réglage BIOS
**Symptôme** : après modification des menus SMU/STAPM, le firmware annonce fast PPT 48 W ; `S93amdtdp` réécrit `system.cpu.tdp=48` à chaque boot et les pourcentages ES (60/100/120 %) donnent 58 W au repos.
**Résolution** : `custom_service` remet `system.cpu.tdp=25` et 15 W de repos après le boot ; les hooks de jeu font le reste.

## Scintillement en 4K60 : câble HDMI
Artefacts même sur image fixe, captures internes (`batocera-screenshot`) propres → défaut en aval du Beelink. Le 4K60 4:4:4 exige ~18 Gbit/s ; remplacer par un câble Premium High Speed a tout réglé.

## La machine ne s'éteint pas : LED allumée, machine morte

Aléatoire, depuis le premier jour, sous Windows comme sous Linux, deux versions de BIOS. Un appui long (6 s) coupe bien l'alimentation → l'EC et le séquencement électrique sont sains, c'est la transition ACPI S5 qui n'aboutit pas. Le service `s5_guard` archive au démarrage suivant le journal noyau du dernier arrêt (pstore EFI) : s'il contient `reboot: Power down`, le noyau avait terminé et rendu la main au firmware — le défaut est matériel. C'est ce qui a été constaté ici, journal complet et sans anomalie. Les erreurs `amdgpu` de fin d'arrêt (`failed to blank crtc!`) sont innocentes : on les retrouve sur des arrêts parfaitement réussis. Atténuations : désarmer toutes les sources de réveil (`s5_guard` le fait pour `GP17`, `XHC0/1`, `GPP1` et le Wake-on-LAN) et, dans le BIOS, `AMD PBS → Wake on PME = Disabled`. Après un blocage, débrancher l'alimentation une trentaine de secondes suffit.

## Accents invisibles dans EmulationStation

Tout caractère non-ASCII s'affiche comme un espace, dans les menus comme dans les vues. Déclencheur : X démarre **sans écran connecté** (téléviseur en veille au redémarrage de la box). ES précharge les codes 32→127 dans un premier atlas de glyphes et rastérise le reste à chaud ; ces atlas-là restent vides. Ni police, ni locale, ni `MaxVRAM` en cause — le correctif amont de ce bug n'existe que pour le renderer GLES20, alors que le build x86/X11 utilise GL21. Corriger : `/etc/init.d/S31emulationstation restart` une fois l'écran allumé (vérifier que le PID d'`xinit` a changé). `custom_service` le fait automatiquement depuis. **À ne pas tenter** : baisser `es.resolution` pour réduire la taille des polices — ES meurt pendant le chargement du thème et le serveur X se fige (tout `xrandr` bloque, seul `kill -9` en vient à bout).

## Appui court sur le bouton d'alimentation sans effet

Le gestionnaire maison mémorisait l'heure d'appui dans un drapeau qu'il n'écrasait pas s'il existait déjà : un relâchement perdu laissait un drapeau orphelin, et tous les appuis suivants héritaient de sa date — donc étaient traités en appui long (menu Quitter au lieu de l'arrêt). Un appui court a ainsi été mesuré à 26 minutes. Correctif : rafraîchir le drapeau au-delà d'une seconde (fenêtre du périphérique ACPI jumeau PWRB/PWRF) et considérer toute durée supérieure à six secondes comme périmée, puisque l'EC coupe l'alimentation à ce stade.

## Moonlight : 197 ms de décodage, le rendu EGL n'était jamais actif

Flux fluide côté serveur mais latence énorme et images perdues côté box. Cause : sans `SDL_VIDEO_X11_FORCE_EGL=1`, SDL ouvre un contexte GLX, le renderer zero-copy de `moonlight-qt` échoue (« Cannot get EGL display ») et Moonlight retombe sur un chemin VAAPI qui plafonne vers 60 images/s — 197 ms de décodage en 4K60, 76 ms et 52 % de pertes en 1080p120. Avec EGL : 0,15 à 0,35 ms. Batocera ne permet pas de passer une variable d'environnement au générateur d'émulateur, d'où le wrapper monté en *bind* sur `/usr/bin/moonlight-qt` (`services/moonlight_egl`). Ajouter `SDL_VIDEO_X11_XRANDR=0` et `SDL_VIDEO_X11_XVIDMODE=0` : sans gestionnaire de fenêtres, `moonlight-qt` passe en plein écran SDL exclusif et choisit lui-même un mode, ce qui ramène le flux à 60 Hz — et un veilleur qui remet le mode pendant l'initialisation du rendu fait planter Mesa.

## Le téléviseur quitte le réseau en veille

Le pilotage par API REST + Wake-on-LAN fonctionne, mais dans les deux modes de « Démarrage à distance » testés, le téléviseur cesse de répondre après une dizaine de minutes de veille : plus de ping, API muette, et le paquet magique ne le réveille plus. Il ne reste joignable que si quelque chose lui parle régulièrement. Vérifier l'économiseur d'énergie du système d'exploitation du téléviseur ; sinon, keepalive depuis un appareil toujours allumé, ou adaptateur USB-CEC. Ne jamais appeler `setWolMode true` : cela rebascule le réglage sur « activation par les applications ».
