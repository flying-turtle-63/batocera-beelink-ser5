#!/bin/bash
# perfmon.sh <label> [durée_s] — échantillonne 1x/s CPU/GPU/puissance/thermique dans /userdata/system/logs/perfmon/<label>.csv
# colonnes : t, cpu_total%, cpu_max_core%, cpu_mhz_avg, gpu_busy%, gpu_sclk_mhz, gpu_mclk_mhz, tctl_c, stapm_w, ppt_fast_w, ppt_slow_w, mem_used_mb, emu_rss_mb
label=${1:-bench}; dur=${2:-90}
out=/userdata/system/logs/perfmon; mkdir -p $out; f=$out/$label.csv
echo "t,cpu_total,cpu_max_core,cpu_mhz,gpu_busy,gpu_sclk,gpu_mclk,tctl,stapm_w,ppt_fast_w,ppt_slow_w,mem_used_mb,emu_rss_mb" > $f
hw=$(for h in /sys/class/hwmon/hwmon*; do grep -q k10temp $h/name 2>/dev/null && echo $h; done | head -1)
read -r -a prev < <(grep -E "^cpu[0-9]+ " /proc/stat | awk '{print $2+$3+$4+$6+$7+$8, $5}' | tr '\n' ' ')
readarray -t pv < <(grep -E "^cpu[0-9]+ " /proc/stat | awk '{b=$2+$3+$4+$6+$7+$8; print b" "$5}')
for ((i=0;i<dur;i++)); do
  sleep 1
  readarray -t cv < <(grep -E "^cpu[0-9]+ " /proc/stat | awk '{b=$2+$3+$4+$6+$7+$8; print b" "$5}')
  tot=0; mx=0; n=${#cv[@]}
  for ((c=0;c<n;c++)); do
    set -- ${pv[$c]}; pb=$1; pi=$2; set -- ${cv[$c]}; cb=$1; ci=$2
    d=$(( (cb-pb)+(ci-pi) )); u=0; [ $d -gt 0 ] && u=$(( (cb-pb)*100/d ))
    tot=$((tot+u)); [ $u -gt $mx ] && mx=$u
  done
  pv=("${cv[@]}"); cpu=$((tot/n))
  mhz=$(awk '/MHz/{s+=$4;c++} END{printf "%d", s/c}' /proc/cpuinfo)
  gb=$(cat /sys/class/drm/card*/device/gpu_busy_percent 2>/dev/null | head -1)
  sclk=$(grep '\*' /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null | head -1 | grep -oE '[0-9]+Mhz' | tr -d Mhz)
  mclk=$(grep '\*' /sys/class/drm/card*/device/pp_dpm_mclk 2>/dev/null | head -1 | grep -oE '[0-9]+Mhz' | tr -d Mhz)
  tctl=$(awk '{printf "%.1f", $1/1000}' $hw/temp1_input 2>/dev/null)
  read -r st pf ps < <(ryzenadj -i 2>/dev/null | awk -F'|' '/STAPM VALUE/{a=$3} /PPT VALUE FAST/{b=$3} /PPT VALUE SLOW/{c=$3} END{gsub(/ /,"",a);gsub(/ /,"",b);gsub(/ /,"",c); print a, b, c}')
  mem=$(free -m | awk '/Mem:/{print $3}')
  rss=$(ps -eo rss,comm --sort=-rss | awk 'NR==2{printf "%d", $1/1024}')
  echo "$(date +%H:%M:%S),$cpu,$mx,$mhz,$gb,$sclk,$mclk,$tctl,$st,$pf,$ps,$mem,$rss" >> $f
done
echo "fin $f"
