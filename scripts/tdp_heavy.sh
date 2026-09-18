#!/bin/bash
# Hook Batocera (/userdata/system/scripts/, appelé avec : gameStart|gameStop système émulateur cœur rom).
# Sur les systèmes lourds : (1) puissance SOUTENUE à 35 W (burn test 35 W : 3,4-3,7 GHz, 84,6 °C max, pas de throttling) — tdp_hooks.sh (exécuté juste avant) pose
# stapm/fast = 30 W mais slow = 24 W et ne touche jamais au PPT APU (25 W d'usine) qui est le vrai
# plafond ; 30 W soutenu = 80-81 °C max mesuré. (2) GPU forcé à sa fréquence max (DPM "high") : en
# auto, l'iGPU reste souvent à 400 MHz sous charge partielle (pacing cassé : 18 Wheeler, N64...).
# Tout est remis (25 W, DPM auto) à l'arrêt du jeu.
event=$1; system=$2
log=/userdata/system/logs/amd-tdp.log
heavy=" gamecube wii psp dreamcast naomi naomi2 atomiswave n64 psx ports steam "
dpm=$(ls /sys/class/drm/card*/device/power_dpm_force_performance_level 2>/dev/null | head -1)
case "$event" in
  gameStart)
    case "$heavy" in *" $system "*) ;; *) exit 0;; esac
    if ryzenadj --stapm-limit=35000 --fast-limit=35000 --slow-limit=35000 --apu-slow-limit=35000 >/dev/null 2>&1; then
      echo "tdp30_heavy: $system -> soutenu 35 W (stapm, fast, slow, apu-slow)" >> "$log"
    else
      echo "tdp30_heavy: ECHEC ryzenadj pour $system" >> "$log"
    fi
    [ -n "$dpm" ] && echo high > "$dpm" 2>/dev/null && echo "tdp30_heavy: GPU DPM high" >> "$log" ;;
  gameStop)
    ryzenadj --apu-slow-limit=25000 >/dev/null 2>&1 && echo "tdp30_heavy: apu-slow remis a 25 W" >> "$log"
    [ -n "$dpm" ] && echo auto > "$dpm" 2>/dev/null ;;
esac
exit 0
