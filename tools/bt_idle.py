#!/usr/bin/env python3
"""Deconnecte les manettes Bluetooth inactives (la DualSense s'eteint alors d'elle-meme).

Surveille les /dev/input/event* des peripheriques Bluetooth (Bus=0005) en ignorant les
capteurs de mouvement (qui emettent en continu). Au bout de `controllers.bt.idle_timeout`
secondes (batocera.conf, defaut 600) sans evenement, `bluetoothctl disconnect <mac>`.
Un appui sur PS reconnecte la manette normalement. Usage : bt_idle.py [timeout_s]
"""
import os, re, select, struct, subprocess, sys, time

EV_KEY, EV_ABS = 1, 3
HATS = {16, 17}       # croix directionnelle
ABS_DELTA = 24        # les sticks de la DualSense bruitent en permanence de +/-1 autour de 127

LOG = "/userdata/system/logs/bt_idle.log"
SKIP = re.compile(r"motion|accelerometer|\bir\b|gyro|imu", re.I)
RESCAN = 10  # s

def log(msg):
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')} {msg}\n")

def timeout_s():
    if len(sys.argv) > 1:
        return int(sys.argv[1])
    try:
        v = subprocess.run(["batocera-settings-get", "controllers.bt.idle_timeout"],
                           capture_output=True, text=True, timeout=5).stdout.strip()
        return int(v) if v else 600
    except Exception:
        return 600

def scan():
    """-> {event_path: (mac, name)} pour les manettes Bluetooth."""
    out, block = {}, {}
    with open("/proc/bus/input/devices") as f:
        for line in list(f) + ["\n"]:
            line = line.rstrip("\n")
            if not line:
                if block.get("bus") == "0005" and block.get("uniq") and not SKIP.search(block.get("name", "")):
                    for h in block.get("handlers", "").split():
                        if h.startswith("event"):
                            out["/dev/input/" + h] = (block["uniq"], block["name"])
                block = {}
            elif line.startswith("I:"):
                m = re.search(r"Bus=(\w+)", line); block["bus"] = m.group(1) if m else ""
            elif line.startswith("N:"):
                block["name"] = line.split("=", 1)[1].strip('"')
            elif line.startswith("U:"):
                block["uniq"] = line.split("=", 1)[1].strip().lower()
            elif line.startswith("H:"):
                block["handlers"] = line.split("=", 1)[1]
    return out

def main():
    tmo = timeout_s()
    log(f"demarrage, timeout={tmo}s")
    fds = {}          # fd -> (path, mac)
    last = {}         # mac -> derniere activite
    names = {}        # mac -> nom
    absval = {}       # (fd, code) -> derniere valeur retenue d'un axe
    next_scan = 0
    while True:
        now = time.time()
        if now >= next_scan:
            next_scan = now + RESCAN
            devs = scan()
            for path, (mac, name) in devs.items():
                if path not in (p for p, _ in fds.values()):
                    try:
                        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
                    except OSError:
                        continue
                    fds[fd] = (path, mac)
                    if mac not in last:
                        last[mac] = now
                        names[mac] = name
                        log(f"suivi {name} ({mac})")
            for fd, (path, mac) in list(fds.items()):
                if path not in devs:
                    os.close(fd); del fds[fd]
            for mac in list(last):
                if mac not in (m for _, m in fds.values()):
                    log(f"parti {names.get(mac)} ({mac})")
                    last.pop(mac, None); names.pop(mac, None)
        try:
            r, _, _ = select.select(list(fds), [], [], 5)
        except (OSError, ValueError):
            r = []
        now = time.time()
        for fd in r:
            path, mac = fds[fd]
            active = False
            try:
                while True:
                    data = os.read(fd, 24 * 128)
                    if not data:
                        break
                    for i in range(0, len(data) - 23, 24):
                        _, _, ty, code, val = struct.unpack("qqHHi", data[i:i + 24])
                        if ty == EV_KEY or (ty == EV_ABS and code in HATS and val):
                            active = True
                        elif ty == EV_ABS:
                            prev = absval.setdefault((fd, code), val)
                            if abs(val - prev) >= ABS_DELTA:
                                active = True
                                absval[(fd, code)] = val
            except BlockingIOError:
                pass
            except OSError:
                os.close(fd); fds.pop(fd, None); next_scan = 0
                continue
            if active:
                last[mac] = now
        for mac, t in list(last.items()):
            if now - t >= tmo:
                log(f"inactif {int(now - t)}s -> deconnexion {names.get(mac)} ({mac})")
                subprocess.run(["bluetoothctl", "disconnect", mac.upper()],
                               capture_output=True, text=True, timeout=15)
                last[mac] = now  # evite de spammer si la deconnexion echoue
                next_scan = 0

if __name__ == "__main__":
    main()
