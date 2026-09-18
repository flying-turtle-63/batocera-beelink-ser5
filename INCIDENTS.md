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
