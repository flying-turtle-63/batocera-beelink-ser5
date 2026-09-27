#!/bin/bash
# Pilotage de la TV Sony Bravia (XR-65A84J) par son API REST + Wake-on-LAN — 2026-09-20.
# Le HDMI du SER5 n'a pas de ligne CEC (pas de /dev/cec*), donc tout passe par le reseau.
# Config : /userdata/system/tv.conf (TV_IP, TV_MAC, TV_PSK, TV_INPUT). Prerequis cote TV : « Demarrage a
# distance » active + Controle IP en « Normal et cle pre-partagee » (WoL active ensuite via setWolMode).
# Precaution : eviter `off` juste avant un arret/reboot du SER5 (le reboot de test du 2026-09-20 a fini en
# blocage S5 ; reproduction deterministe passee ensuite, donc coincidence probable — la TV en veille garde le HPD).
#   tv.sh on      allume la TV (WoL + setPowerStatus) puis bascule sur TV_INPUT si elle n'y est pas deja,
#                 et coupe le son de la TV si TV_MUTE_AT_ON=1 (demande du 2026-09-20 ; telecommande pour le remettre)
#   tv.sh mute|unmute  coupe / remet le son de la TV
#   tv.sh off     met la TV en veille
#   tv.sh input   bascule sur TV_INPUT sans toucher a l'alimentation
#   tv.sh status  etat d'alimentation + entree active
conf=/userdata/system/tv.conf
[ -r "$conf" ] && . "$conf"
TV_IP=${TV_IP:-CHANGEME_tv_ip}; TV_MAC=${TV_MAC:-CHANGEME_tv_mac}; TV_INPUT=${TV_INPUT:-extInput:hdmi?port=4}
log=/userdata/system/logs/display.log
say() { echo "tv: $(date +%T) $*" >> "$log"; echo "$*"; }

api() { # api <service> <methode> <params-json> [version]
  curl -s -m 4 -H "X-Auth-PSK: $TV_PSK" "http://$TV_IP/sony/$1" \
    -d "{\"method\":\"$2\",\"id\":1,\"params\":[$3],\"version\":\"${4:-1.0}\"}" 2>/dev/null
}
power() { api system getPowerStatus "" | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p'; }
# entree active : le champ "status":"true" de getCurrentExternalInputsStatus
current_input() { api avContent getCurrentExternalInputsStatus "" 1.1 | tr '{' '\n' | grep '"status":"true"' | sed -n 's/.*"uri":"\([^"]*\)".*/\1/p'; }
wol() { python3 - "$TV_MAC" <<'PY'
import socket,sys
pkt=b"\xff"*6+bytes.fromhex(sys.argv[1].replace(":",""))*16
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET,socket.SO_BROADCAST,1)
for p in (9,7): s.sendto(pkt,("255.255.255.255",p))
PY
}
mute() { api audio setAudioMute '{"status":true}' >/dev/null; say "son coupe"; }
switch_input() {
  for i in $(seq 1 10); do
    [ "$(current_input)" = "$TV_INPUT" ] && { say "entree $TV_INPUT active"; return 0; }
    r=$(api avContent setPlayContent "{\"uri\":\"$TV_INPUT\"}")
    case "$r" in *'"result"'*) say "bascule sur $TV_INPUT"; return 0;; esac
    sleep 2   # la TV renvoie "Illegal State" tant qu'elle n'a pas fini de s'allumer
  done
  say "echec bascule sur $TV_INPUT ($r)"; return 1
}

case "$1" in
  on)
    wol
    st=$(power)
    if [ "$st" != "active" ]; then
      # la TV peut mettre quelques secondes a repondre au reseau apres le WoL
      for i in $(seq 1 15); do st=$(power); [ -n "$st" ] && break; wol; sleep 2; done
      [ -z "$st" ] && { say "TV injoignable en $TV_IP"; exit 1; }
      api system setPowerStatus '{"status":true}' >/dev/null
      for i in $(seq 1 15); do [ "$(power)" = "active" ] && break; sleep 2; done
      say "allumage ($st -> $(power))"
    fi
    switch_input
    [ "$TV_MUTE_AT_ON" = "1" ] && mute ;;
  mute)   mute ;;
  unmute) api audio setAudioMute '{"status":false}' >/dev/null; say "son remis" ;;
  off)    api system setPowerStatus '{"status":false}' >/dev/null; say "mise en veille ($(power))" ;;
  input)  switch_input ;;
  status) echo "power=$(power) input=$(current_input)" ;;
  *) echo "usage: $0 on|off|input|mute|unmute|status"; exit 1 ;;
esac
