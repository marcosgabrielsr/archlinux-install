#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ========== Utilidades/erros ==========
log() { echo "[$(date +%T)] $*"; }
err() { echo "[$(date +%T)] ERRO: $*" >&2; }
die() { err "$@"; exit 1; }
trap 'err "Falha na linha $LINENO"; exit 1' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Comando obrigatório não encontrado: $1"; }

confirm() {
  local q="${1:-Confirmar?} [s/N] "
  read -r -p "$q" ans || true
  [[ "${ans,,}" == "s" || "${ans,,}" == "y" ]]
}

# ========== Parâmetros (podem ser sobrescritos por env ou flags) ==========
DISK="${DISK:-/dev/nvme0n1}"          # Disco de destino (ex.: /dev/nvme0n1, /dev/sda)
HOSTNAME="${HOSTNAME:-archlinux}"
USERNAME="${USERNAME:-mgs}"
PASSWORD="${PASSWORD:-}"               # Recomenda-se passar via env: PASSWORD='...' ./install.sh
LOCALE="${LOCALE:-pt_BR.UTF-8}"
KEYMAP="${KEYMAP:-br-abnt2}"
TIMEZONE="${TIMEZONE:-America/Campo_Grande}"
SHELL_BIN="${SHELL_BIN:-/bin/bash}"
SET_WHEEL_SUDO="${SET_WHEEL_SUDO:-1}"
SKIP_CONFIRM="${SKIP_CONFIRM:-0}"

# Pacotes base (mantém sua chamada usando variáveis)
BASE_PACKAGES="${BASE_PACKAGES:-linux linux-firmware sudo networkmanager iwd grub efibootmgr base-devel vim reflector}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-}"

usage() {
  cat <<EOF
Uso: $(basename "$0") [--yes]

Variáveis aceitáveis via ENV:
  DISK=/dev/nvme0n1 | /dev/sda
  HOSTNAME=archlinux
  USERNAME=mgs
  PASSWORD=...
  LOCALE=pt_BR.UTF-8
  KEYMAP=br-abnt2
  TIMEZONE=America/Campo_Grande
  SHELL_BIN=/bin/bash
  SET_WHEEL_SUDO=1|0
  BASE_PACKAGES="..."   (padrão já inclui grub, efibootmgr, networkmanager, iwd, etc.)
  EXTRA_PACKAGES="..."  (opcionais)
  SKIP_CONFIRM=1        (pular confirmação destrutiva)

Exemplos:
  PASSWORD='minha-senha' TIMEZONE='America/Sao_Paulo' ./install.sh
  DISK=/dev/sda SKIP_CONFIRM=1 ./install.sh --yes
EOF
}

# Flags simples
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage; exit 0
fi
if [[ "${1:-}" == "--yes" ]]; then
  SKIP_CONFIRM=1
fi

# ========== Pré-checagens ==========
[[ $EUID -eq 0 ]] || die "Precisa rodar como root."
[[ -f /etc/arch-release ]] || die "Este script é para Arch Linux (ambiente live ou chroot)."
require_cmd parted
require_cmd mkfs.fat
require_cmd mkfs.ext4
require_cmd mount
require_cmd pacstrap
require_cmd genfstab
require_cmd arch-chroot
require_cmd grub-install
require_cmd grub-mkconfig
require_cmd visudo

# Internet mínima (opcional, mas recomendada)
if ! ping -c1 -W1 archlinux.org >/dev/null 2>&1; then
  log "Aviso: sem conectividade com archlinux.org; pacotes podem falhar."
fi

# Evita travas do pacman
if fuser /var/lib/pacman/db.lck >/dev/null 2>&1; then
  die "pacman está em uso (db.lck). Tente novamente."
fi

# Sufixo de partição (nvme/mmc usam 'p', sata/virtio não)
part_suf() {
  local d="$1"
  if [[ "$d" =~ (nvme|mmcblk) ]]; then
    echo "p"
  else
    echo ""
  fi
}

P="$(part_suf "$DISK")"
EFI="${DISK}${P}1"
ROOT="${DISK}${P}2"
HOME="${DISK}${P}3"

# ========== Particionamento (DESTRUTIVO) ==========
log "Disco alvo: $DISK"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | sed 's/^/  /'
if [[ "$SKIP_CONFIRM" != "1" ]]; then
  echo
  echo "⚠️  Isto vai APAGAR COMPLETAMENTE o conteúdo de $DISK:"
  echo "  - GPT nova"
  echo "  - Partição 1 (EFI):    1MiB–513MiB (FAT32, 'esp on')"
  echo "  - Partição 2 (root):   513MiB–50.5GiB (ext4)"
  echo "  - Partição 3 (home):   50.5GiB–100% (ext4)"
  confirm "Deseja prosseguir?" || die "Cancelado pelo usuário."
fi

log "Criando tabela GPT e partições…"
# Desmonta algo pendurado
umount -R /mnt >/dev/null 2>&1 || true
swapoff -a >/dev/null 2>&1 || true

# Zera assinaturas e cria GPT limpa
wipefs -af "$DISK" || true
parted --script "$DISK" \
  mklabel gpt \
  mkpart "EFI system partition" fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart "root partition" ext4 513MiB 50.5GiB \
  mkpart "home partition" ext4 50.5GiB 100%

partprobe "$DISK" || true
sleep 1

log "Partições criadas:"
lsblk -o NAME,SIZE,TYPE,PARTLABEL,MOUNTPOINT "$DISK" | sed 's/^/  /'

# ========== Formatação ==========
log "Formatando sistemas de arquivos…"
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"
mkfs.ext4 -F "$HOME"

# ========== Montagem ==========
log "Montando partições…"
mount "$ROOT" /mnt
install -d /mnt/boot/efi /mnt/home
mount "$EFI" /mnt/boot/efi
mount "$HOME" /mnt/home

log "Layout montado:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | sed 's/^/  /'

# ========== Instalação base ==========
log "Instalando sistema base com pacstrap…"
# Mantém seu padrão (base + variáveis)
pacstrap -K /mnt base ${BASE_PACKAGES} ${EXTRA_PACKAGES} --noconfirm

# ========== Fstab ==========
log "Gerando fstab…"
genfstab -U /mnt >> /mnt/etc/fstab
log "fstab gerado em /mnt/etc/fstab"

# ========== Configuração no chroot ==========
log "Entrando no sistema (arch-chroot) para configurar…"

arch-chroot /mnt /bin/bash -e <<CHROOT
set -Eeuo pipefail
IFS=\$'\n\t'
log(){ echo "[\$(date +%T)] [chroot] \$*"; }
err(){ echo "[\$(date +%T)] [chroot] ERRO: \$*" >&2; }
trap 'err "Falha na linha \$LINENO"; exit 1' ERR

# Locale
if ! grep -q "^${LOCALE} UTF-8" /etc/locale.gen; then
  sed -i "s/^#\s*${LOCALE}\s\+UTF-8/${LOCALE} UTF-8/" /etc/locale.gen || echo "${LOCALE} UTF-8" >> /etc/locale.gen
fi
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Timezone, NTP e relógio
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
timedatectl set-timezone "${TIMEZONE}" || true
timedatectl set-ntp true || true
hwclock --systohc --utc || true

# Hostname e hosts
echo "${HOSTNAME}" > /etc/hostname
cat >/etc/hosts <<EOF_H
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF_H

# Pacman: habilita paralelismo leve, colore
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
  sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
fi
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Mirrorlist com reflector (se instalado)
if command -v reflector >/dev/null 2>&1; then
  reflector --country "Brazil,Argentina,Chile" --latest 20 --sort rate --save /etc/pacman.d/mirrorlist || true
fi

# Sudoers (grupo wheel)
if [[ "${SET_WHEEL_SUDO}" == "1" ]]; then
  tmp=\$(mktemp)
  echo "%wheel ALL=(ALL:ALL) ALL" > "\$tmp"
  visudo -cf "\$tmp"
  install -Dm440 "\$tmp" /etc/sudoers.d/00-wheel
  rm -f "\$tmp"
fi

# Usuário
if ! id -u "${USERNAME}" >/dev/null 2>&1; then
  useradd -m -G wheel -s "${SHELL_BIN}" "${USERNAME}"
fi
# senha será definida depois (fora do chroot) para evitar eco em logs

# NetworkManager + backend iwd (drop-in idempotente)
install -d /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-iwd.conf <<'EOF_NM'
[device]
wifi.backend=iwd
EOF_NM
systemctl disable --now iwd.service >/dev/null 2>&1 || true
systemctl disable --now wpa_supplicant.service >/dev/null 2>&1 || true
systemctl enable NetworkManager.service

# Bootloader: GRUB UEFI em /boot/efi
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=archlinux --recheck
grub-mkconfig -o /boot/grub/grub.cfg

log "Configuração no chroot finalizada."
CHROOT

# Define senha do usuário (fora do chroot para não vazar echo)
if [[ -z "${PASSWORD}" ]]; then
  echo "Digite a senha para ${USERNAME}:"
  read -r -s pass1
  echo "Confirme a senha:"
  read -r -s pass2
  [[ "\$pass1" == "\$pass2" ]] || die "Senhas não conferem."
  PASSWORD="\$pass1"
fi
echo "${USERNAME}:${PASSWORD}" | arch-chroot /mnt chpasswd

log "Instalação concluída 🎉"
echo
echo "Resumo:"
echo "  Disco        : $DISK"
echo "  Partições    : $EFI (EFI), $ROOT (root), $HOME (home)"
echo "  Hostname     : $HOSTNAME"
echo "  Usuário      : $USERNAME (wheel=${SET_WHEEL_SUDO})"
echo "  Locale       : $LOCALE"
echo "  Keymap       : $KEYMAP"
echo "  Timezone     : $TIMEZONE"
echo
echo "Próximos passos:"
echo "  - Reinicie, conecte-se ao Wi-Fi com 'nmtui' ou 'nmcli' se necessário."
echo "  - Após boot, considere instalar microcódigo (intel-ucode/amd-ucode) e drivers gráficos."
