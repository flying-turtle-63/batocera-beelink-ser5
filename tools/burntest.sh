#!/bin/bash
# burntest.sh <watts> <durée_s> : charge 12 threads (openssl) sous limite de puissance fixée, échantillonne 2 s.
W=${1:-30}; D=${2:-300}; out=/userdata/system/logs/perfmon/burn_${W}w.csv
pgrep -af "retroarch|dolphin-emu|PPSSPP|redream" | grep -vq "bash -c" && { echo "jeu en cours, abandon"; exit 1; }
for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > $c; done
ryzenadj --stapm-limit=$((W*1000)) --fast-limit=$((W*1000)) --slow-limit=$((W*1000)) --apu-slow-limit=$((W*1000)) >/dev/null
hw=$(for h in /sys/class/hwmon/hwmon*; do grep -q k10temp $h/name 2>/dev/null && echo $h; done | head -1)
echo "t,tctl,stapm_w,ppt_fast_w,mhz_min,mhz_avg,mhz_max,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11" > $out
( openssl speed -multi 12 -seconds $D sha256 >/dev/null 2>&1 ) &
BURN=$!
sleep 2
while kill -0 $BURN 2>/dev/null; do
  t=$(awk '{printf "%.1f",$1/1000}' $hw/temp1_input)
  read -r st pf < <(ryzenadj -i 2>/dev/null | awk -F'|' '/STAPM VALUE/{a=$3} /PPT VALUE FAST/{b=$3} END{gsub(/ /,"",a);gsub(/ /,"",b); print a, b}')
  freqs=$(grep MHz /proc/cpuinfo | awk '{printf "%d,", $4}' | sed 's/,$//')
  stats=$(echo "$freqs" | tr , '\n' | awk 'NR==1{mn=$1;mx=$1} {s+=$1; if($1<mn)mn=$1; if($1>mx)mx=$1} END{printf "%d,%d,%d", mn, s/NR, mx}')
  echo "$(date +%H:%M:%S),$t,$st,$pf,$stats,$freqs" >> $out
  sleep 2
done
# retour : limites Batocera (ES) et gouverneur système
/usr/bin/batocera-amd-tdp 15 >/dev/null 2>&1; ryzenadj --apu-slow-limit=25000 >/dev/null 2>&1
g=$(batocera-settings-get system.cpu.governor); for c in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo ${g:-powersave} > $c; done
echo "fin $out"
