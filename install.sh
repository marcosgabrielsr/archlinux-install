#!/bin/bash
set -e # faz o script parar se houver erro

# --- VARIÁVEIS PRINCIPAIS ---
DISK="/dev/nvme0n1"                 # disco onde instalar
HOSTNAME="archlinux"
USERNAME="mgs"
PASSWORD="mgs1562"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
TIMEZONE="America/Campo_Grande"     # fuso horário
EFI_PART_SIZE="512MiB"              # tamanho da partição EFI
SWAP_SIZE="2G"                      # tamanho da partição SWAP

# Pacotes adicionais
EXTRA_PACKAGES="nvim sudo networkmanager base-deve git"

# --- FUNÇÕES AUXILIARES ---
msg() {
    echo -e "\n==> $*\n"
}

# --- INÍCIO ---
msg "Iniciando instação automatizada do Arch Linux"

# Verifica se rodando como root (na live)
if [[ $EUID -ne 0 ]]; then
    echo "Este script precisa ser executado como root."
    exit 1
fi

# --- PARTIÇÕES ---
msg "Iniciando partições do disco $DISK"

# Construindo tabela de partições
parted --script $DISK \
    mklabel gpt \
    mkpart "EFI system partition" fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart "root partition" ext4 513MiB 50.5GiB \
    mkpart "home partition" ext4 50.5GiB 100%

# Verificando esquema de partições
parted $DISK print

EFI="${DISK}p1"
ROOT="${DISK}p2"
HOME="${DISK}p3"

# Formatando partições
mkfs.fat -F32 $EFI
mkfs.ext4 -F  $ROOT
mkfs.ext4 -F  $HOME

# Montando partições
mount $ROOT /mnt
mkdir -p /mnt/{boot/efi,home}
mount $EFI /mnt/boot/efi
mount $HOME /mnt/home

msg "Partições montadas com sucesso!"

# --- MIRRORLIST ---
msg "Atualizando mirrorlist"

msg "Instalando reflector"
pacman -Syu --noconfirm
pacman -S --noconfirm reflector

# Parametros do reflector
COUNTRY="Brazil,Argentina,Chile"
LATEST="20"
SORT="rate"
PATH_SAVE="/etc/pacman.d/mirrorlist"

reflector --country $COUNTRY --latest $LATEST --sort $SORT --save $PATH_SAVE
MIRROR="Server = https://mirror.ufscar.br/archlinux/\$repo/os/\$arch"
sed -i "1i $MIRROR" /etc/pacman.d/mirrorlist

msg "Mirrorlist atualizada com sucesso!"

