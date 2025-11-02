#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

err() { echo "[$(date +%T)] ERRO: $*" >&2; }
die() { err "$@"; exit 1; }
trap 'err "Falha na linha $LINENO"; exit 1' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"; }

set_timezone() {
    local tz="${1:-${TIMEZONE:-America/Campo_Grande}}"
    [[ -z "$tz" ]] && die "TIMEZONE não definido"
    [[ -e "/usr/share/zoneinfo/$tz" ]] || die "Timezone inválido: $tz"

    ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
    echo "$tz" > /etc/timezone || true
    timedatectl set-timezone "$tz" || true
    echo "[OK] Timezone definido para $tz"
}

synchronize_clock() {
    require_cmd hwclock
    hwclock --systohc --utc
    echo "[OK] hwclock sincronizado (--utc)"
}

synchronize_internet_clock() {
    require_cmd timedatectl
    timedatectl set-ntp true
    # systemd-timesyncd pode estar ausente em algumas ISOs; tente iniciar se existir
    if systemctl list-unit-files | grep -q '^systemd-timesyncd.service'; then
        systemctl enable --now systemd-timesyncd.service || true
    fi
    echo "[OK] NTP habilitado"
}
