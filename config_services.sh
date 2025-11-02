#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

err() { echo "[$(date +%T)] ERRO: $*" >&2; }
die() { err "$@"; exit 1; }
trap 'err "Falha na linha $LINENO"; exit 1' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"; }

pkg_install() {
    require_cmd pacman
    pacman -Sy --needed --noconfirm "$@"
}

enable_networking() {
    pkg_install networkmanager iwd

    # Configura backend iwd via drop-in (idempotente)
    local d="/etc/NetworkManager/conf.d"
    local f="$d/10-iwd.conf"
    install -d -m 755 "$d"
    cat > "$f" <<'EOF'
[device]
wifi.backend=iwd
EOF

    # Não habilite iwd.service — o NM usa iwd como backend, sem serviço separado
    systemctl disable --now iwd.service >/dev/null 2>&1 || true

    # Elimina possíveis conflitos com wpa_supplicant
    systemctl disable --now wpa_supplicant.service >/dev/null 2>&1 || true

    systemctl enable --now NetworkManager.service
    systemctl reload NetworkManager.service || true
    echo "[OK] NetworkManager ativo com backend iwd"
}

enable_base_services() {
    # Adicione aqui outros serviços essenciais que você queira padronizar
    # Ex.: bluetooth, printing, avahi, etc. — somente se instalados
    for svc in bluetooth.service cups.service avahi-daemon.service; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            systemctl enable --now "$svc" || true
        fi
    done
}
