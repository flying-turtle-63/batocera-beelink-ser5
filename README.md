# Batocera sur Beelink SER5 (Ryzen 5 5560U) — configuration optimisée

> **English summary** — Tuned Batocera 43 configuration for a Beelink SER5 mini-PC (Ryzen 5 5560U, Vega 6 iGPU, 16 GB DDR4-3200, 4K60 TV). What you get: a 4K display profile that actually fills the screen (bezel fix), per-emulator settings sized for the Vega 6, a power hook that lifts the hidden 25 W APU cap to 35 W in heavy games, **a fan-control service that finally cools the CPU** (the stock EC curve follows a board thermistor and never spins up), idle-power fixes, a Wi-Fi driver blacklist that stops the machine from freezing, and the scripts used to measure all of it. French below.

Configuration **Batocera 43.1** d'un **Beelink SER5** : Ryzen 5 5560U (6C/12T Zen 3), iGPU **Vega 6** (RADV), 16 Go DDR4-3200 double canal, NVMe, TV 4K 60 Hz (1080p à 120 Hz accepté), câble HDMI 18 Gbit/s. Tout ce qui est ici a été **mesuré** (charge GPU/CPU, fréquences, puissance réelle, températures, frametimes) avant d'être retenu ; les valeurs rejetées et pourquoi sont dans [`docs/MESURES.md`](docs/MESURES.md), les pannes rencontrées dans [`INCIDENTS.md`](INCIDENTS.md).

Aucune rom, aucun BIOS, aucune clé, aucun média dans ce dépôt.

## Contenu

| Fichier | Rôle | Où l'installer |
|---|---|---|
| `batocera.conf` | configuration complète (profil 4K, réglages par émulateur, TDP, gouverneur, HUD) — secrets remplacés par `CHANGEME_*` | `/userdata/system/batocera.conf` (fusionner, ne pas écraser aveuglément) |
| `services/fanctl` | **pilotage du ventilateur sur la température CPU réelle** | `/userdata/system/services/` |
| `services/wlan_off` | neutralise la carte Wi-Fi/BT MediaTek (driver instable) | `/userdata/system/services/` |
| `services/custom_service` | garde-fou affichage (sortie *primary*), gouverneur/EPP de repos, base TDP | `/userdata/system/services/` |
| `scripts/tdp_heavy.sh` | hook Batocera : 35 W soutenus + GPU à sa fréquence max pendant les jeux lourds | `/userdata/system/scripts/` (exécutable) |
| `etc/modprobe.d/blacklist-wifi-mt7921.conf` | blacklist du driver `mt7921e` | `/etc/modprobe.d/` puis `batocera-save-overlay` |
| `drirc` | `mesa_glthread` pour les émulateurs OpenGL | `/userdata/system/.drirc` |
| `shaders/` | set de shaders **FSR 1** (EASU + RCAS, sans grain de film) pour les cœurs 3D libretro | `/userdata/shaders/` |
| `tools/perfmon.sh`, `bench.sh`, `burntest.sh` | mesure (1 Hz : CPU/GPU/MHz/puissance/Tctl), banc via l'API EmulationStation, burn test à puissance fixée | `/userdata/system/` |

Activer les services : `system.services=custom_service wlan_off fanctl` dans `batocera.conf` (ou menu ES → Système → Services).

## 1. Affichage 4K

- `global.videomode=3840x2160.60.00` pour tous les systèmes : le coût GPU est piloté par la **résolution interne** de chaque émulateur, pas par la sortie.
- **`global.bezel_stretch=1` est indispensable en 4K** : sans lui, configgen redimensionne l'image du bezel (×2) mais garde le `custom_viewport` en coordonnées 1080p → le jeu occupe un quart de l'écran.
- `es.resolution=1920x1080.60.00` dans **`/boot/batocera-boot.conf`** (Batocera 43 lit cette clé là, pas dans `batocera.conf`) : l'interface ES en 1080p divise par deux la charge GPU au repos (48 % → 21 %). Les jeux restent en 4K (une bascule HDMI par lancement).

## 2. Émulateurs (Vega 6 = ~1,2 TFLOPS, 35 W partagés avec le CPU)

| Système | Réglage retenu | Mesure |
|---|---|---|
| NES, SNES, Mega Drive, GB/GBA, Lynx, Neo Geo, FBNeo… | natif, `sharp-bilinear-simple`, `runahead=1` + `secondinstance=1` (2 frames sur NES/SNES/MD) | négligeable |
| **GameCube** | Dolphin Vulkan, **`dual_core=1` (OFF par défaut dans Batocera !)**, ubershaders hybrides, **3×** (1920×1584), AF 4×, MSAA 0 | deux jeux de course en 2× : GPU 32–35 % → 3× |
| **Wii** | idem, **2×** | jeu de course : un thread CPU à 88 % → CPU-bound, 2× suffit |
| N64 | libretro **mupen64plus-next** + GLideN64 1280×960, 3-point, shader FSR | GPU 58 % |
| PSX | swanstation 4× + PGXP, shader FSR | — |
| Dreamcast | redream **5×** (3200×2400) ; flycast Vulkan 1920×1440 + FSR pour quelques titres, au cas par cas | jeu d'arcade 5× : GPU 47 %, 0 image > 20 ms |
| Naomi / Atomiswave | flycast Vulkan 1280×960 (Naomi 2 : 960×720), FSR | un titre à 30 fps natif : pacing irrégulier (DPM) |
| PSP | PPSSPP Vulkan **8× (4K natif)**, 6× pour les titres les plus lourds | jeu de course 5× : GPU 15 % |
| prboom (ports) | 1920×1200 | — |

Le set de shaders `fsr` (dossier `shaders/`) fait l'upscale EASU + RCAS des rendus 960–1440 lignes vers le viewport 4K ; la copie du preset dans `/userdata/shaders/` a `FSR_FILMGRAIN = 0` (celui de Batocera ajoute un grain).

Pièges rencontrés : `gamecube.powermode=powersaver` traînait dans la conf (gouverneur bridé en jeu) ; la batterie d'une DualSense apparaît dans `/sys/class/power_supply/` et le hook `powermode` croit être sur batterie → mettre **`global.batterymode`** en plus de `global.powermode`.

## 3. Puissance, fréquences, ventilation

### Le plafond caché : PPT APU 25 W
Le slider ES « TDP » (`global.tdp=120`) donne 30 W en pic / 24 W soutenu, mais `batocera-amd-tdp` ne touche jamais au **PPT APU** (`ryzenadj --apu-slow-limit`, 25 W d'usine) : c'est lui qui borne la puissance soutenue. Le hook `scripts/tdp_heavy.sh` (exécuté **après** celui de Batocera à `gameStart`, donc jamais écrasé — contrairement à `custom.sh`) pose stapm/fast/slow/APU = **35 W** sur les systèmes lourds et force `power_dpm_force_performance_level=high` (en `auto`, l'iGPU retombe à 400–830 MHz sous charge partielle) ; retour à 25 W / `auto` à `gameStop`.

### La vraie cause thermique : le ventilateur
Le ventilateur est piloté par le Super I/O **IT8772E** dont la régulation automatique suit une **thermistance de carte** (49–58 °C quand le CPU passe de 46 à 88 °C) avec la courbe figée du BIOS (« PC Health » : off 30 / start 50 / full 90 °C). Il plafonne à ~1 700 tr/min alors qu'il monte à 5 000. La table « Fan Control » du menu SMU (AMD CBS) est inerte. **`services/fanctl`** charge `it87` (`ignore_resource_conflict=1`), passe `pwm2` en manuel et suit **Tctl** (k10temp) par paliers 45/70/110/160/210/255 à 52/60/68/74/80 °C, hystérésis 3 °C, retour à l'automatique si le service s'arrête.

Résultat (burn 12 threads à 30 W) : **83–88 °C → 70 °C**. En jeu lourd à 35 W : 69–74 °C. Cet exemplaire avait déjà été repasté (pâte thermique changée ~2 ans avant ces mesures) : le repaste seul ne suffisait pas, la régulation du ventilateur était le vrai facteur. Surélever le boîtier d'1 cm aide aussi.

### Repos
`system.cpu.governor=powersave` (= mode dynamique d'`amd-pstate` en mode *active*, EPP `balance_performance`, pas un bridage) : repos 3,4 GHz / 18 W / 61 °C → 2,1 GHz / 11 W / 48–58 °C. `global.powermode=highperformance` remet `performance` à chaque lancement. Attention : `S93amdtdp` réécrit `system.cpu.tdp` à chaque boot à partir du PPT annoncé par le firmware (48 W après certains réglages BIOS) et les pourcentages ES supposent 25 W → `custom_service` force la base à 25 W et 15 W de repos après le boot.

### BIOS (Aptio / AMI, menus AMD CBS accessibles sur ce modèle)

| Menu | Réglage | Valeur retenue | Pourquoi |
|---|---|---|---|
| Advanced → AMD CBS → NBIO → GFX Configuration | **iGPU Configuration** | `UMA_SPECIFIED` | seul mode où la taille choisie ci-dessous est appliquée (`UMA_AUTO` = choix du firmware, souvent 512 Mo–2 Go ; `UMA_GAME_OPTIMIZED` = préréglage non contrôlable) |
| idem | **UMA Frame Buffer Size** | **4 Go** (choix : 2/3/4/8) | 3 Go d'origine ; 4 Go laissent 12 Go au système. 8 Go est à éviter : les émulateurs lourds montent à 6–7 Go de RSS côté hôte, sans swap on frôlerait le plantage, et sur un APU VRAM et GTT sont la même DDR4 (la GTT de ~6 Go sert déjà de débordement). Vérification sous Linux : `mem_info_vram_total` = 4,0 Go, GTT 5,8 Go |
| idem | GPU Host Translation Cache | `Auto` | sans effet sur le rendu, un forçage peut gêner `amdgpu` |
| Advanced → AMD CBS → SMU Common Options | System Configuration | « 25W POR Configuration-3 » (le max proposé, sinon 10/15 W/Auto) | c'est la table d'origine du plafond PPT APU 25 W, contourné par le hook `tdp_heavy.sh` |
| idem | Fan Control (table manuelle) | **inerte sur ce modèle** — laisser `Auto` | le ventilateur est piloté par le Super I/O IT8772E, pas par le SMU ; voir `services/fanctl` |
| idem | System Temperature Tracking (STT) | `Disabled` | bridage « température de peau » conçu pour les portables |
| idem | STAPM Control | à laisser par défaut | Batocera et le hook réécrivent les limites à chaque lancement/arrêt ; toute valeur BIOS plus haute change le PPT annoncé au boot et donc la base que `S93amdtdp` recopie dans `system.cpu.tdp` (voir *Repos*) |
| Advanced → PC Health Status | Smart CPU_Fan | valeurs figées (off 30 / start 50 / full 90 °C, slope 1) — non modifiables | c'est cette courbe EC que `fanctl` remplace |
| Advanced → USB Configuration | Legacy USB / XHCI hand-off | `Enabled` (défaut) | nécessaires au clavier BIOS et à Linux, rien à changer |
| Advanced (page AMD) | DPTC interface `Auto`, STT sensor reporting `Disabled`, tensions VDDP/VDDIO | défaut | ne pas toucher aux tensions ; Curve Optimizer / undervolt sont refusés par le SMU sur ce firmware (`ryzenadj --set-coall` rejeté) |

Effet de bord observé après ces changements : le firmware annonce au boot STAPM 37,5 / fast 48 / slow 37,5 W au lieu de 25/30/24 ; comme Batocera re-détecte `system.cpu.tdp` depuis le PPT FAST à chaque démarrage, `custom_service` force la base à 25 W pour garder le sens des pourcentages ES.

## 4. Stabilité

- **Driver Wi-Fi MediaTek `mt7921e`** (carte inutilisée, box en Ethernet) : boucle `driver own failed` toutes les secondes, machine quasi figée, `rmmod` bloqué en état D, `reboot` impossible → blacklist (`etc/modprobe.d/`) + `services/wlan_off`. Bonus : la radio Bluetooth de la même carte doublonnait le dongle Realtek et faisait mouliner `bluetoothd` → éteinte au boot.
- **Sortie *primary* X perdue** après un jeu qui change de fréquence HDMI (ex. 1080p120) → tous les lancements plantent (`videoMode.getCurrentResolution: invalid literal for int()`) → `custom_service` la rétablit toutes les 5 s sans toucher au mode vidéo.
- **`killall -9` d'un émulateur peut emporter EmulationStation**, dont le wrapper boucle alors 6×/s (écran noir) → `/etc/init.d/S31emulationstation restart` ; pour arrêter un jeu, préférer l'API (`/emukill`) ou la commande réseau de RetroArch.
- Câble HDMI : en 4K60 4:4:4 (18 Gbit/s), un câble limite scintille ; comparer une capture interne (`batocera-screenshot`) avec l'écran avant d'accuser l'émulateur.

## 5. Mesurer avant de régler

`tools/perfmon.sh <label> <secondes>` écrit un CSV à 1 Hz (CPU total et cœur le plus chargé, MHz, GPU busy/sclk/mclk, Tctl, STAPM/PPT réels via `ryzenadj -i`, RAM). `tools/bench.sh` lance une rom via l'API ES, attend le mode démo, mesure, arrête. `tools/burntest.sh <W> <s>` charge 12 threads à puissance fixée (attention : `openssl speed -seconds N` enchaîne 6 tailles de bloc). MangoHud (couche Vulkan fournie par Batocera) donne les frametimes : `global.hud=custom` + `hud_custom` avec `autostart_log` pour logger en CSV ; `gpu_power` est faux sur cet iGPU (65,5 W constants), la puissance package est sur la ligne CPU.

Règle de cadence : sur une sortie 60 Hz seuls 60 et 30 fps sont réguliers ; à **120 Hz** : 60, 40, 30, 24. Un framerate non multiple donne des micro-saccades même s'il est plus élevé.

## Licence

MIT. Fait avec l'aide de Claude Code ; les mesures datent de septembre 2026 sur Batocera 43.1, Mesa 26.1 / RADV.
