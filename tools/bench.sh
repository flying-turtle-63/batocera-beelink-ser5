#!/bin/bash
# bench.sh <label> <rom_absolu> <attente_s> <duree_s> — lance via l'API ES, attend l'attract/démo, échantillonne, arrête.
label=$1; rom=$2; wait=${3:-60}; dur=${4:-90}
log=/userdata/system/logs/perfmon/_bench.log
echo "== $(date +%H:%M:%S) $label : $rom" >> $log
if pgrep -af "retroarch|dolphin-emu|PPSSPP|redream" | grep -vq bash; then echo "   OCCUPE, saut" >> $log; exit 1; fi
before=$(ls /userdata/system/logs/mangohud/*.csv 2>/dev/null | wc -l)
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST --data-binary "$rom" http://127.0.0.1:1234/launch)
echo "   launch http $code, attente ${wait}s" >> $log
sleep "$wait"
if ! pgrep -af "retroarch|dolphin-emu|PPSSPP|redream" | grep -vq bash; then echo "   ECHEC : emulateur absent apres l attente" >> $log; exit 2; fi
/userdata/system/perfmon.sh "$label" "$dur" >/dev/null
curl -s -o /dev/null -X POST http://127.0.0.1:1234/emukill; sleep 8; pgrep -af "retroarch|dolphin-emu|PPSSPP|redream" | grep -vq bash && killall retroarch dolphin-emu PPSSPP redream 2>/dev/null; sleep 4
killall -9 retroarch dolphin-emu PPSSPP redream 2>/dev/null
f=$(ls -t /userdata/system/logs/mangohud/*.csv 2>/dev/null | head -1)
after=$(ls /userdata/system/logs/mangohud/*.csv 2>/dev/null | wc -l)
if [ "$after" -gt "$before" ] && [ -n "$f" ]; then mv "$f" "/userdata/system/logs/mangohud/$label.csv"; echo "   mangohud -> $label.csv ($(wc -l < /userdata/system/logs/mangohud/$label.csv) lignes)" >> $log; else echo "   mangohud : pas de log" >> $log; fi
for i in $(seq 1 20); do curl -s -o /dev/null http://127.0.0.1:1234/systems && break; sleep 3; done
echo "   fin $(date +%H:%M:%S)" >> $log
