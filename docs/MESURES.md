# Mesures (Batocera 43.1, Mesa 26.1 / RADV, septembre 2026)

Méthode : `tools/perfmon.sh` (1 Hz : CPU total / cœur max / MHz, GPU busy / sclk, Tctl, STAPM et PPT réels via `ryzenadj -i`) + MangoHud en log CSV (fps, frametime). Sortie 4K pour tous les jeux ci-dessous. « Cœur max » = thread le plus chargé (un thread à ~100 % = goulet CPU d'émulation).

## Banc automatique (modes démo / attract, 90 s)

| Jeu (réglage) | fps moy / 1 % low | GPU busy | Cœur max | PPT | Verdict |
|---|---|---|---|---|---|
| F-Zero GX (GC, Dolphin 2×) | 59,9 / 59,8 | 32 % | 25 % | 12 W | énorme marge → GC passé en 3× |
| Mario Kart Double Dash (GC 2×) | 60,4 / 47,4 | 35 % | 24 % (pic 64) | 12 W | palier de 4 s à 48 fps (shader/pacing) |
| Mario Kart Wii (Wii 2×) | 60,6 / 59,4 | 32 % | **88 %** | 18 W | CPU-bound sur un thread → reste en 2× |
| Daytona USA (redream 5×) | 60,1 / 53,7 | 47 % (pics 71) | 34 % | 20 W | 5× confortable |
| 18 Wheeler (Naomi, flycast) | 37 irrégulier | 34 % | 38 % | 18 W | 30 fps natif + pacing cassé (alternance 21/43 ms, sclk 400 MHz) |
| Burnout Legends (PSP 5×) | 30,0 (33,4 ms constants) | 15 % | 33 % | 14 W | 30 fps natif → 8× possible |
| Mario Kart 64 (N64, GLideN64 + FSR) | — | 58 % | 26 % | 17 W | marge |

Enseignements : rien n'est power-bound aux réglages ES (STAPM ≤ 21 W, PPT slow ≤ 24 W) ; le plafond réel était le PPT APU 25 W ; le GPU passe 40–78 % du temps à 400 MHz par sous-charge (DPM auto) → forcé `high` en jeu.

## Burn tests (12 threads `openssl`, gouverneur `performance`)

| Puissance | Ventilation | Fréquence tous cœurs | Tctl | Throttling |
|---|---|---|---|---|
| 30 W | courbe EC d'origine | 3 240–3 267 MHz | 80–82 °C | aucun (−0,7 % de 65 à 82 °C) |
| 35 W | courbe EC d'origine | 3 430–3 750 MHz (+9,6 %) | 84,6 °C max | aucun |
| 30 W | table SMU manuelle du BIOS | 3 400–3 550 MHz | **85 °C** | la table est inerte, c'est l'EC qui pilote |
| **30 W** | **`fanctl` (PWM sur Tctl)** | 3 260–3 350 MHz | **70 °C**, 3 600 tr/min | — |

Référence communautaire : SER5 repasté à 35 W = 84 °C / 3 243 MHz. Le repaste n'est pas le sujet, la sonde du ventilateur l'est.

## En jeu, avant / après (mêmes réglages de jeu, 35 W)

| Situation | Tctl | GPU | Ventilo |
|---|---|---|---|
| 35 W, ventilation EC | **88,8 °C** (throttling, micro-saccades) | 65 % | ~1 700 tr/min |
| 35 W, `fanctl` + boîtier surélevé | **69–74 °C** | 81 % | 3 600–4 400 tr/min |

## Règle de cadence
Sortie 60 Hz : seuls 60 et 30 fps sont réguliers. Sortie 120 Hz (1080p sur cette TV) : 60, 40, 30, 24. Un framerate intermédiaire, même plus élevé, se ressent comme des micro-saccades — mieux vaut un cap régulier qu'un « sans limite ».
