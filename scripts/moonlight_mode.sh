#!/bin/bash
# Hook Batocera (/userdata/system/scripts/, appelé avec : gameStart|gameStop système émulateur cœur rom).
# Le générateur Moonlight de Batocera ignore <system>.videomode : le flux s'affiche dans la résolution
# de l'accueil ES (1080p60 depuis le 17/09), donc un flux 4K etait decode puis reduit en 1080p.
# Ce hook applique le mode de sortie voulu pendant le flux (clé moonlight.display_mode, ex. 1920x1080.120.00
# ou 3840x2160.60.00) et remet la résolution ES (es.resolution) à l'arrêt.
event=$1; system=$2; rom=$(basename "${5:-}")
[ "$system" = "moonlight" ] || [ "$system" = "steam" ] || exit 0
# Profil par tuile : steam["<fichier>"].display_mode / .resolution_override dans batocera.conf priment sur les cles
# globales moonlight.* (ex. tuile "Steam 4K60.steam" = 3840x2160.60.00 sans override). Le hook transmet l override
# au wrapper de services/moonlight_egl via /tmp/moonlight_override (vide = laisser le drapeau du generateur).
tile_key() { # <cle> -> valeur par tuile si definie (meme vide), sinon valeur globale moonlight.<cle>
  local v
  if [ -n "$rom" ] && grep -qE "^$system\[\"$rom\"\]\.$1=" "$conf"; then
    grep -E "^$system\[\"$rom\"\]\.$1=" "$conf" | head -1 | cut -d= -f2-
  else
    grep -E "^moonlight.$1=" "$conf" | head -1 | cut -d= -f2-
  fi
}
log=/userdata/system/logs/display.log
conf=/userdata/system/batocera.conf
out=$(grep -E "^global.videooutput=" $conf | cut -d= -f2); out=${out:-HDMI-1}
d=$(pgrep -a xinit | grep -oE " :[0-9]" | head -1 | tr -d " "); export DISPLAY=${d:-:0}
# Modes absents de l EDID de la Sony XR-65A84J mais acceptes par elle (testes 2026-09-19/20), tous sous la limite
# HDMI 2.0 (600 MHz) : 2560x1440@120 (CVT-RB, 497 MHz), 2880x1620@100 (CVT-RB, 516 MHz), 2880x1620@120 (blanking
# reduit sous la norme, 586 MHz). Ajoutes a la volee sous le nom WxH_RR ; TV en "Mode large = Plein 1" pour remplir l ecran.
custom_modeline() { # WxH RR -> modeline (vide si inconnu)
  case "$1_$2" in
    2560x1440_120) echo "497.25 2560 2608 2640 2720 1440 1443 1448 1525 +hsync -vsync" ;;
    2880x1620_100) echo "516.50 2880 2928 2960 3040 1620 1623 1627 1699 +hsync -vsync" ;;
    2880x1620_120) echo "586.08 2880 2888 2920 2960 1620 1623 1627 1650 +hsync -vsync" ;;
  esac
}
ensure_custom_mode() {
  local ml name; ml=$(custom_modeline "$1" "$2"); [ -n "$ml" ] || return 1
  name="${1}_$2"
  xrandr 2>/dev/null | grep -q "^ *$name " || {
    xrandr --newmode "$name" $ml 2>>"$log"
    xrandr --addmode "$out" "$name" 2>>"$log"
  }
  echo "$name"
}
setmode() { # WxH.R.RR
  local m=$1 res rate custom
  res=${m%%.*}; rate=${m#*.}; rate=${rate%%.*}
  [ -n "$res" ] && [ -n "$rate" ] || return 1
  if custom=$(ensure_custom_mode "$res" "$rate"); then
    xrandr --output "$out" --mode "$custom" 2>>"$log" && echo "moonlight_mode: $(date +%T) $event -> $custom" >> "$log"
  else
    xrandr --output "$out" --mode "$res" --rate "$rate" 2>>"$log" && echo "moonlight_mode: $(date +%T) $event -> $res @ $rate Hz" >> "$log"
  fi
}
case "$event" in
  gameStart)
    # PC eteint ? On le reveille (via un script maison optionnel), ecran
    # d attente sur la TV ; cle moonlight.pc_wake=0 pour desactiver. Sunshine deja la : retour immediat.
    if [ "$(grep -E "^moonlight.pc_wake=" $conf | cut -d= -f2)" != "0" ] && ! timeout 2 bash -c "exec 3<>/dev/tcp/CHANGEME_pc_ip/47989" 2>/dev/null; then
      /userdata/system/tools/pc-wake.sh (optionnel, absent de ce depot : propre a chaque installation) >> "$log" 2>&1 || echo "moonlight_mode: $(date +%T) reveil du PC en echec, Moonlight va afficher son erreur" >> "$log"
    fi
    tile_key resolution_override > /tmp/moonlight_override
    m=$(tile_key display_mode); [ -n "$m" ] || exit 0; setmode "$m"
    # moonlight-qt (sans gestionnaire de fenetres => plein ecran SDL exclusif) re-applique lui-meme un mode
    # a la connexion du flux et retombe sur 1920x1080@60.01 : un veilleur detache remet le mode voulu
    # pendant 90 s tant que moonlight-qt vit (le hook lui-meme rend la main tout de suite).
    res=${m%%.*}; rate=${m#*.}; rate=${rate%%.*}
    setsid bash -c "echo \$\$ > /tmp/moonlight_mode.pid; for i in \$(seq 1 45); do sleep 2; pgrep -f moonlight-qt >/dev/null || exit 0; cur=\$(xrandr | grep -oE '[0-9]+x[0-9]+[_0-9]* .*\*' | head -1); echo \"\$cur\" | grep -qE \"^${res}(_$rate)? .*\b$rate\.[0-9]+\*|^${res}_$rate .*\*\" && continue; if xrandr | grep -q \"^ *${res}_$rate \"; then xrandr --output $out --mode ${res}_$rate; else xrandr --output $out --mode $res --rate $rate; fi && echo \"moonlight_mode: \$(date +%T) mode re-applique $res @ $rate Hz (etait: \$cur)\" >> $log; done" >/dev/null 2>&1 < /dev/null &
    ;;
  gameStop)  rm -f /tmp/moonlight_override
    [ -f /tmp/moonlight_mode.pid ] && { kill "$(cat /tmp/moonlight_mode.pid)" 2>/dev/null; rm -f /tmp/moonlight_mode.pid; }
    m=$(grep -E "^es.resolution=" $conf | cut -d= -f2); setmode "${m:-1920x1080.60.00}" ;;
esac
exit 0
