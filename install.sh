#!/bin/bash
# install.sh — déploie la configuration Batocera "Beelink SER5 5560U" sur une box Batocera fraîchement installée.
#
# Usage (sur la box, en root) :
#   ./install.sh            # installe tout (sauvegardes dans /userdata/system/backup-ser5-<date>/)
#   ./install.sh --dry-run  # montre ce qui serait fait, ne modifie rien
#   ./install.sh --no-wifi  # ne blackliste pas la carte Wi-Fi (si vous en avez besoin)
#   ./install.sh --no-conf  # ne touche pas à batocera.conf (services/scripts/outils seulement)
#   ./install.sh --uninstall
#
# Exemple depuis un PC : scp -r . root@batocera.local:/userdata/system/ser5-setup && ssh root@batocera.local /userdata/system/ser5-setup/install.sh
#
# Ce script est idempotent : il peut être relancé après une mise à jour de Batocera (l'overlay /etc et les
# services sont réappliqués). Il ne touche ni aux roms, ni aux BIOS, ni aux sauvegardes.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
DRY=0; WIFI=1; CONF=1; UNINSTALL=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --no-wifi) WIFI=0;; --no-conf) CONF=0;; --uninstall) UNINSTALL=1;;
  -h|--help) sed -n 2,14p "$0"; exit 0;; *) echo "option inconnue : $a" >&2; exit 1;; esac; done

SYS=/userdata/system
BK="$SYS/backup-ser5-$(date +%Y%m%d-%H%M%S)"
CONF_FILE="$SYS/batocera.conf"
log()  { printf '\033[1;32m[ser5]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ser5] ATTENTION :\033[0m %s\n' "$*"; }
run()  { if [ $DRY -eq 1 ]; then echo "  (dry-run) $*"; else eval "$@"; fi; }
backup() { [ -e "$1" ] || return 0; run "mkdir -p '$BK' && cp -a '$1' '$BK/'"; }
install_file() { # src dst mode
  local src="$HERE/$1" dst="$2" mode="${3:-644}"
  [ -f "$src" ] || { warn "fichier manquant dans le paquet : $1"; return 1; }
  backup "$dst"
  run "mkdir -p '$(dirname "$dst")' && cp '$src' '$dst' && chmod $mode '$dst'"
  log "installé : $dst"
}

# --- garde-fous -------------------------------------------------------------------------------------
[ "$(id -u)" = 0 ] || { echo "à lancer en root sur la box Batocera" >&2; exit 1; }
command -v batocera-settings-set >/dev/null || { echo "batocera-settings-set introuvable : ce n'est pas une box Batocera ?" >&2; exit 1; }
ver=$(batocera-es-swissknife --version 2>/dev/null | grep -oE '^[0-9]+'); [ -n "$ver" ] && [ "$ver" -lt 43 ] && warn "Batocera $ver détecté : testé sur 43 uniquement"
cpu=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2)
echo "$cpu" | grep -q "5560U" || warn "CPU différent du Ryzen 5 5560U (${cpu# }) : les valeurs de puissance/ventilation (35 W, table PWM, sonde it87) sont spécifiques au Beelink SER5 — relisez services/fanctl et scripts/tdp_heavy.sh avant de les activer"
if [ $UNINSTALL -eq 1 ]; then
  log "désinstallation des services/scripts (batocera.conf n'est pas modifié)"
  run "rm -f $SYS/services/fanctl $SYS/services/wlan_off $SYS/services/custom_service $SYS/scripts/tdp_heavy.sh $SYS/.drirc /etc/modprobe.d/blacklist-wifi-mt7921.conf"
  run "rm -rf /userdata/shaders/configs/fsr /userdata/shaders/edge-smoothing/fsr"
  run "batocera-settings-set system.services ''"
  run "batocera-save-overlay >/dev/null"
  log "terminé ; redémarrez. Les clés de batocera.conf restent en place (voir conf/settings.conf pour les retirer à la main)."
  exit 0
fi
log "sauvegardes dans $BK"

# --- 1. services et scripts ------------------------------------------------------------------------
install_file services/custom_service "$SYS/services/custom_service" 755
install_file services/fanctl          "$SYS/services/fanctl"          755
SERVICES="custom_service fanctl"
if [ $WIFI -eq 1 ]; then
  if [ "$(batocera-settings-get wifi.enabled 2>/dev/null)" = "1" ]; then
    warn "wifi.enabled=1 : le Wi-Fi est activé, la carte MediaTek ne sera PAS blacklistée (relancez avec Ethernet + wifi.enabled=0, ou --no-wifi pour taire cet avertissement)"
  else
    install_file services/wlan_off "$SYS/services/wlan_off" 755
    install_file etc/modprobe.d/blacklist-wifi-mt7921.conf /etc/modprobe.d/blacklist-wifi-mt7921.conf 644
    SERVICES="custom_service wlan_off fanctl"
    log "blacklist Wi-Fi posée dans l'overlay (batocera-save-overlay à la fin)"
  fi
fi
install_file scripts/tdp_heavy.sh "$SYS/scripts/tdp_heavy.sh" 755
warn "tout fichier exécutable dans $SYS/scripts/ est un hook gameStart/gameStop : n'y déposez rien d'autre"

# --- 2. Mesa / shaders / outils --------------------------------------------------------------------
install_file drirc "$SYS/.drirc" 644
install_file shaders/configs/fsr/rendering-defaults.yml /userdata/shaders/configs/fsr/rendering-defaults.yml 644
install_file shaders/edge-smoothing/fsr/fsr.slangp      /userdata/shaders/edge-smoothing/fsr/fsr.slangp 644
for t in perfmon.sh bench.sh burntest.sh; do install_file "tools/$t" "$SYS/$t" 755; done

# --- 3. batocera.conf ------------------------------------------------------------------------------
if [ $CONF -eq 1 ]; then
  backup "$CONF_FILE"
  n=0
  while IFS= read -r line; do
    line="${line%%$'\r'}"
    [ -z "$line" ] && continue; [ "${line:0:1}" = "#" ] && continue
    key="${line%%=*}"; val="${line#*=}"
    if [ $DRY -eq 1 ]; then echo "  (dry-run) $key=$val"; else batocera-settings-set "$key" "$val" >/dev/null 2>&1 || warn "clé refusée : $key"; fi
    n=$((n+1))
  done < "$HERE/conf/settings.conf"
  log "$n réglages appliqués depuis conf/settings.conf"
  run "batocera-settings-set system.services '$SERVICES' >/dev/null"
  log "system.services=$SERVICES"
  # ES en 1080p : es.resolution vit dans batocera.conf ; S65values4boot le recopie dans /boot/batocera-boot.conf
  # à chaque démarrage (éditer /boot directement ne sert à rien : la valeur serait écrasée au reboot suivant).
  run "batocera-settings-set es.resolution 1920x1080.60.00 >/dev/null"
  log "es.resolution=1920x1080.60.00 (interface ES en 1080p, jeux en 4K ; appliqué au prochain démarrage)"
else
  run "batocera-settings-set system.services '$SERVICES' >/dev/null"
fi

# --- 4. overlay et fin -----------------------------------------------------------------------------
run "batocera-save-overlay >/dev/null 2>&1"
log "overlay sauvegardé (blacklist Wi-Fi persistante)"
cat <<EOF

Installation terminée. Reste à faire à la main :
  - BIOS : iGPU Configuration = UMA_SPECIFIED, UMA Frame Buffer Size = 4 Go (voir README §3) ;
  - vérifier la sortie vidéo : global.videooutput=$(batocera-settings-get global.videooutput 2>/dev/null || echo "?") — adaptez si votre TV n'est pas sur HDMI-1 ;
  - si votre TV n'accepte pas le 4K60, remettez global.videomode (menu ES → Paramètres des jeux → Mode vidéo) ;
  - redémarrer : reboot

Après redémarrage, contrôles : lsmod | grep -c '^mt7' (0 attendu), tail /userdata/system/logs/fanctl.log (le ventilo suit Tctl),
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor (powersave au repos), ryzenadj -i | grep 'PPT LIMIT' (35 W en jeu lourd).
EOF
