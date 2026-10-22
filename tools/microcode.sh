#!/bin/bash
# Microcode AMD charge au demarrage (early loading) — 2026-10-22.
# Le BIOS FP655U509 charge 0x0a50000d ; AMD publie 0x0a500012 pour Cezanne (CPUID 00a50f00) dans linux-firmware
# (amd-ucode/microcode_amd_fam19h.bin, signe par l'« AMD Microcode Signing Key », empreinte du patch presente dans la
# table amd_shas.c du noyau 6.18). Batocera 43.1 ne livre pas ce fichier et n'a pas de rechargement a chaud : seul le
# chargement precoce marche. Methode dracut : une archive cpio NON compressee (kernel/x86/microcode/AuthenticAMD.bin)
# placee devant l'initrd gzip ; le noyau la lit avant tout le reste. Les fichiers de boot (syslinux/grub) ne changent pas.
# Une mise a jour Batocera remplace initrd.gz : le microcode disparait alors sans rien casser (`status` le dit, `on` le remet).
#   microcode.sh on      prefixe /userdata/system/microcode/amd-ucode.cpio a /boot/boot/initrd.gz (original : initrd.gz.stock)
#   microcode.sh off     remet l'initrd d'origine (retour arriere ; effet au prochain demarrage)
#   microcode.sh status  revision chargee, protections du noyau, etat de l'initrd
dir=/userdata/system/microcode
cpio=$dir/amd-ucode.cpio
initrd=/boot/boot/initrd.gz
stock=/boot/boot/initrd.gz.stock
log=/userdata/system/logs/display.log
say() { echo "microcode: $(date +%T) $*" >> "$log"; echo "$*"; }
die() { say "ERREUR : $*"; exit 1; }
has_ucode() { [ "$(head -c 6 "$initrd")" = "070701" ]; }   # magie cpio newc ; un initrd d'origine commence par 1f 8b (gzip)
rw() { mount -o remount,rw /boot || die "remontage de /boot en ecriture impossible"; trap 'sync; mount -o remount,ro /boot' EXIT; }

case "$1" in
  on)
    [ -r "$cpio" ] || die "$cpio absent"
    if has_ucode; then say "deja actif ($initrd commence par l'archive microcode)"; exit 0; fi
    rw
    # initrd.gz courant = initrd d'origine (premiere fois, ou apres une mise a jour Batocera qui l'a remplace)
    cp "$initrd" "$stock.tmp" && mv "$stock.tmp" "$stock" || die "copie de l'initrd d'origine impossible"
    cat "$cpio" "$stock" > "$initrd.tmp" && sync || die "assemblage impossible"
    n=$(stat -c %s "$cpio")
    cmp -s <(head -c "$n" "$initrd.tmp") "$cpio" && cmp -s <(tail -c +$((n + 1)) "$initrd.tmp") "$stock" \
      || { rm -f "$initrd.tmp"; die "verification de l'initrd assemble en echec, rien change"; }
    mv "$initrd.tmp" "$initrd" || die "remplacement de $initrd impossible"
    say "active : $initrd = microcode ($n o) + initrd d'origine ; effet au prochain demarrage"
    ;;
  off)
    has_ucode || { say "deja inactif ($initrd est l'initrd d'origine)"; exit 0; }
    [ -r "$stock" ] || die "$stock absent : pas de copie d'origine"
    rw
    cp "$stock" "$initrd.tmp" && sync && mv "$initrd.tmp" "$initrd" || die "restauration impossible"
    say "desactive : initrd d'origine remis ; effet au prochain demarrage"
    ;;
  status)
    echo "revision chargee : $(grep -m1 microcode /proc/cpuinfo | awk '{print $3}')"
    dmesg | grep -i "microcode:" | sed 's/^/  /'
    for v in spec_rstack_overflow tsa; do echo "  $v: $(cat /sys/devices/system/cpu/vulnerabilities/$v 2>/dev/null)"; done
    if has_ucode; then echo "initrd : microcode prefixe (actif au prochain demarrage s'il ne l'est pas deja)"
    else echo "initrd : d'origine (microcode.sh on pour activer)"; fi
    ;;
  *) sed -n 2,11p "$0"; exit 1 ;;
esac
