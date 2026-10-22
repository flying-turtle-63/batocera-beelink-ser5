#!/usr/bin/env python3
# Fabrique l'archive microcode precoce attendue par microcode.sh — 2026-10-22.
# Batocera n'a pas d'outil cpio ; python3 suffit. Sortie : cpio "newc" NON compresse contenant
# kernel/x86/microcode/AuthenticAMD.bin, complete a 512 octets, a placer devant l'initrd gzip.
#   make-ucode-cpio.py microcode_amd_fam19h.bin amd-ucode.cpio
# Le fichier d'entree vient de linux-firmware (amd-ucode/microcode_amd_fam19h.bin). Le script affiche le patch
# qu'il contient pour le CPU courant si /proc/cpuinfo est lisible, et refuse un fichier qui n'est pas un conteneur AMD.
import struct
import sys
import time

if len(sys.argv) != 3:
    sys.exit("usage : make-ucode-cpio.py <microcode_amd_famXXh.bin> <sortie.cpio>")
data = open(sys.argv[1], "rb").read()
if data[:4] != b"DMA\x00":
    sys.exit("pas un conteneur microcode AMD (magie DMA absente)")

# patch prevu pour ce CPU (signature CPUID lue dans /proc/cpuinfo) — information seulement
try:
    info = dict(l.split(":", 1) for l in open("/proc/cpuinfo") if ":" in l)
    fam, mod, step = (int(info[k].strip()) for k in ("cpu family\t", "model\t\t", "stepping\t"))
    ext = fam - 0xF if fam > 0xF else 0
    cpuid = (ext << 20) | ((mod >> 4) << 16) | (min(fam, 0xF) << 8) | ((mod & 0xF) << 4) | step
    _, eqlen = struct.unpack_from("<II", data, 4)
    eq = {}
    for i in range(eqlen // 16):
        inst, _, _, eid, _ = struct.unpack_from("<IIIHH", data, 12 + 16 * i)
        if inst:
            eq[eid] = inst
    off = 12 + eqlen
    found = None
    while off < len(data):
        _, plen = struct.unpack_from("<II", data, off)
        pid = struct.unpack_from("<I", data, off + 12)[0]
        if eq.get(struct.unpack_from("<H", data, off + 32)[0]) == cpuid:
            found = pid
        off += 8 + plen
    print("CPUID %08x : %s" % (cpuid, "patch 0x%08x" % found if found else "AUCUN patch dans ce fichier"))
except (OSError, KeyError, ValueError):
    pass


def entry(name, mode, body=b""):
    name = name.encode() + b"\x00"
    hdr = "070701" + "".join("%08x" % v for v in (
        entry.ino, mode, 0, 0, 1 if mode & 0o100000 else 2, int(time.time()), len(body),
        0, 0, 0, 0, len(name), 0))
    entry.ino += 1
    out = hdr.encode() + name
    out += b"\x00" * (-len(out) % 4)
    return out + body + b"\x00" * (-len(body) % 4)


entry.ino = 1
cpio = b"".join((
    entry("kernel", 0o40755),
    entry("kernel/x86", 0o40755),
    entry("kernel/x86/microcode", 0o40755),
    entry("kernel/x86/microcode/AuthenticAMD.bin", 0o100644, data),
    entry("TRAILER!!!", 0),
))
cpio += b"\x00" * (-len(cpio) % 512)
open(sys.argv[2], "wb").write(cpio)
print("%s : %d octets" % (sys.argv[2], len(cpio)))
