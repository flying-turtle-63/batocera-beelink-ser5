#!/bin/bash
# Gestionnaire du bouton d'alimentation du Beelink (appelé par triggerhappy via
# /userdata/system/configs/multimedia_keys.conf, argument 1 = appui, 0 = relâchement).
#
# Remplace le comportement stock (batocera-shutdown -> /sbin/shutdown immédiat dès
# l'appui, jeu et EmulationStation tués sans sauvegarde) par :
#   - appui court  (< LONG_PRESS_CS) : arrêt propre — le jeu en cours est quitté via
#     l'API ES (emukill, l'émulateur reçoit SIGTERM et vide ses sauvegardes), puis ES
#     est quitté proprement (/quit + drapeau /tmp/shutdown.please : sauvegarde des
#     gamelists/réglages, pas de relance par le wrapper) et la machine est éteinte.
#   - appui long   (>= LONG_PRESS_CS) : menu « Quitter » d'EmulationStation, pour
#     choisir éteindre / redémarrer / veille à la manette.
#   - si ES ne répond pas : /sbin/shutdown -P -h now (comportement stock).
#   - dans les deux cas d'arrêt, un script optionnel /userdata/system/tools/tv.sh (absent ici) est appele pour
#     mettre l ecran en veille ; sans lui, cette etape est ignoree ; pas dans le menu Quitter (on peut y
#     choisir redémarrer).
#
# Journal : /userdata/system/logs/power-button.log

LONG_PRESS_CS=200          # seuil appui long, en centièmes de seconde
TWIN_CS=100                # en deçà, un 2e appui = le périphérique ACPI jumeau (PWRB/PWRF)
STALE_CS=600               # au-delà, le drapeau d'appui est périmé (l'EC coupe vers 6 s)
EMUKILL_TIMEOUT=15         # secondes max d'attente de la fin du jeu
ES_API="http://localhost:1234"
PRESS_FLAG="/var/run/power-button.pressed"
LAST_ACTION="/var/run/power-button.last"
LOG="/userdata/system/logs/power-button.log"
DRYRUN="${POWER_BUTTON_DRYRUN:-0}"   # =1 : journalise sans éteindre (tests)

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
act() { if [ "$DRYRUN" = "1" ]; then log "DRYRUN: $*"; else "$@"; fi; }
now_cs() { awk '{ print int($1 * 100) }' /proc/uptime; }

# 000 = ES injoignable, 201 = aucun jeu, autre = jeu en cours
es_running_game() {
    local code
    code=$(curl --connect-timeout 1 -s -o /dev/null -w '%{http_code}' "$ES_API/runningGame" 2>/dev/null)
    echo "${code:-000}"
}

tv_standby() {
    [ -x /userdata/system/tools/tv.sh ] || return 0
    act /userdata/system/tools/tv.sh off >/dev/null 2>&1 && log "TV mise en veille"
}

graceful_shutdown() {
    local status
    status=$(es_running_game)
    if [ "$status" = "000" ]; then
        log "ES injoignable, arrêt système direct"
        tv_standby
        act /sbin/shutdown -P -h now
        return
    fi
    if [ "$status" != "201" ]; then
        log "jeu en cours, fermeture propre (emukill)"
        act curl -s -o /dev/null "$ES_API/emukill"
        local i=0
        while [ $i -lt $((EMUKILL_TIMEOUT * 2)) ]; do
            sleep 0.5
            [ "$(es_running_game)" = "201" ] && break
            i=$((i + 1))
        done
        [ "$(es_running_game)" = "201" ] && log "jeu fermé" || log "jeu toujours actif après ${EMUKILL_TIMEOUT}s, on continue"
    fi
    log "arrêt via EmulationStation"
    tv_standby
    # L'API ES n'a pas de route /shutdown : on dépose le drapeau du menu Quitter (le wrapper
    # emulationstation-standalone ne relance alors pas ES), on fait quitter ES proprement
    # (gamelists/réglages sauvegardés), puis on éteint.
    act touch /tmp/shutdown.please
    act curl -s -o /dev/null "$ES_API/quit"
    local i=0
    while [ $i -lt 20 ] && pgrep -f "^emulationstation " >/dev/null; do sleep 0.5; i=$((i + 1)); done
    act /sbin/shutdown -P -h now
}

es_quit_menu() {
    if [ "$(es_running_game)" = "201" ]; then
        log "appui long : menu Quitter d'ES"
        act curl -s -o /dev/null "$ES_API/quit?confirm=menu"
    else
        # en jeu ou ES absent : on se rabat sur l'arrêt propre
        graceful_shutdown
    fi
}

case "$1" in
    1)
        # Deux périphériques ACPI (PWRB, PWRF) émettent KEY_POWER : les deux appuis arrivent
        # à quelques millisecondes d'intervalle, on ne garde que le premier. Mais un drapeau
        # plus vieux que TWIN_CS est forcément un orphelin (relâchement jamais reçu) : sans ce
        # rafraîchissement, TOUS les appuis suivants héritaient de sa date et étaient classés
        # « appui long » — le bouton ouvrait le menu Quitter au lieu d'éteindre (27/09).
        if [ -e "$PRESS_FLAG" ] && [ $(( $(now_cs) - $(cat "$PRESS_FLAG" 2>/dev/null || echo 0) )) -lt "$TWIN_CS" ]; then
            :
        else
            now_cs > "$PRESS_FLAG"
        fi
        ;;
    0)
        [ -e "$PRESS_FLAG" ] || exit 0
        pressed=$(cat "$PRESS_FLAG")
        # celui qui réussit à supprimer le drapeau agit (dédoublonnage)
        rm "$PRESS_FLAG" 2>/dev/null || exit 0
        held=$(( $(now_cs) - pressed ))
        # anti-rebond : une seule action toutes les 5 s
        if [ -e "$LAST_ACTION" ] && [ $(( $(date +%s) - $(date +%s -r "$LAST_ACTION") )) -lt 5 ]; then
            log "appui ignoré (anti-rebond)"
            exit 0
        fi
        touch "$LAST_ACTION"
        # Garde-fou : au-delà de STALE_CS l'EC aurait déjà coupé l'alimentation matériellement
        # (maintien ~6 s), donc une telle durée ne peut venir que d'un drapeau périmé : on la
        # traite en appui bref plutôt que d'ouvrir le menu Quitter.
        if [ "$held" -ge "$STALE_CS" ]; then
            log "bouton relâché après ${held} cs — drapeau périmé, traité en appui bref"
            held=0
        else
            log "bouton relâché après ${held} cs"
        fi
        if [ "$held" -ge "$LONG_PRESS_CS" ]; then
            es_quit_menu
        else
            graceful_shutdown
        fi
        ;;
esac
