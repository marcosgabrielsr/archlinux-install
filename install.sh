#!/bin/bash

# Importando arquivos com funções
source config_services.sh
source time_date_config.sh

set -e # faz o script parar se houver erro

# --- VARIÁVEIS PRINCIPAIS ---
DISK="/dev/nvme0n1"                 # disco onde instalar
HOSTNAME="archlinux"
USERNAME="mgs"
PASSWORD="mgs1562"
LOCALE="pt_BR.UTF-8"
KEYMAP="br-abnt2"
EFI_PART_SIZE="512MiB"              # tamanho da partição EFI
SWAP_SIZE="2G"                      # tamanho da partição SWAP

# Pacotes base
BASE_PACKAGES="base base-devel linux linux-headers linux-firmware"

# Pacotes adicionais
EXTRA_PACKAGES="nano nvim"

# Pacotes finais
FINAL_PACKAGES="dosfstools mtools networkmanager iwd grub efibootmgr amd-ucode"

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
    mkpart EFI fat32 1MiB 513MiB \
    set 1 esp on \
    mkpart root ext4 513MiB 50.5GiB \
    mkpart home ext4 50.5GiB 100%

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
MIRROR="Server = https://mirror.osbeck.com/archlinux/\$repo/os/\$arch"
sed -i "1i $MIRROR" /etc/pacman.d/mirrorlist

pacman -Syu --noconfirm

msg "Mirrorlist atualizada com sucesso!"

# --- INSTALANDO BASE DO SISTEMA ---
msg "Instalando pacotes:
 - Pacotes Base: $BASE_PACKAGES
- Pacotes extras: $EXTRA_PACKAGES"

pacstrap -K /mnt base $BASE_PACKAGES $EXTRA_PACKAGES --noconfirm

msg "Pacotes instalados com sucesso!"

# --- CONFIGURANDO O FSTAB ---
msg "Gerando arquivo fstab"

genfstab -U /mnt >> /mnt/etc/fstab

msg "fstab gerado com sucesso!"

# --- ENTRANDO NO SISTEMA ---
msg "Acessando sistema local"

arch-chroot

msg "Sistema acessado com sucesso!"

# --- EDITANDO PACMAN.CONF ---
msg "Configurando pacman.conf"

# Habilitar cores
sed -i 's/^#Color/Color/' /etc/pacman.conf

# Habilitar downloads paralelos (exemplo: 5)
if grep -q '^#ParallelDownloads' /etc/pacman.conf; then
    sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
elif ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
    echo "ParallelDownloads = 5" >> /etc/pacman.conf
fi

msg "pacman.conf atualizado com sucesso!"

# --- DEFININDO FUSO HORÁRIO E RELOGIO ---
msg "Configurando fuso horario e relogio"
set_timezone
synchronize_clock
synchronize_internet_clock
msg "fuso horario e relogios configurados com sucesso!"

# --- CONFIGURANDO LINGUAGENS ---
msg "Configurando idiomas"

# Habilitar en_US.UTF-8 e pt_BR.UTF-8
sed -i 's/^#en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' "/etc/locale.gen"
sed -i 's/^#pt_BR\.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' "/etc/locale.gen"

locale-gen

# Definir o idioma principal (en_US)
echo "LANG=en_US.UTF-8" > /etc/locale.conf
# Opcional: adicionar variável para português secundário
echo "LC_MESSAGES=pt_BR.UTF-8" >> /etc/locale.conf
msg "Idiomas configurados com sucesso!"

# --- CONFIGURANDO LAYOUT DO TECLADO ---
msg "Configurando layout do teclado"
echo "KEYMAP=br-abnt2" >> /etc/vconsole.conf
msg "layout configurado com sucesso!"

# --- CONFIGURANDO HOSTNAME ---
msg "Configurando hostname"
echo "$HOSTNAME" >> /etc/hostname
msg "Hostname configurando com sucesso!"

# --- CONFIGURANDO HOSTS ---
msg "Configurando arquivo /etc/hosts/"

echo "127.0.0.1         localhost" >> /etc/hosts
echo "::1               localhost" >> /etc/hosts
echo "127.0.1.1         $HOSTNAME.localdomain   $HOSTNAME" >> /etc/hosts

msg "Configuracao do arquivo /etc/hosts/ concluida com sucesso"

# --- CONFIGURANDO SENHA DO ROOT ---
echo "Configurando senha do adm"
passwd
echo "Senha configurada com sucesso!"

# --- CRIANDO USUÁRIO COMUM ---
msg "Criando usuario"
# Ativando grupo wheel
msg "Ativando grupo wheel no diretorio /etc/sudoers"

# Descomenta a linha do grupo wheel no sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
msg "Grupo wheel ativado com sucesso!"

useradd -mG wheel $USERNAME
passwd $USERNAME

# --- INSTALANDO PACOTES FINAIS ---
msg "Instalando pacotes da etapa final"
msg "Instalando: $FINAL_PACKAGES"
pacman -S $FINAL_PACKAGES
msg "Pacotes instalados com sucesso!"

# --- CONFIGURANDO GRUB ---
msg "Configurando grub"
msg "Instalando grub"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=archlinux --recheck
msg "grub instalado com sucesso!"
grub-mkconfig -o /boot/grub/grub.cfg
msg "grub configurado com sucesso!"

# --- HABILITANDO NETWORK MANAGER ---
msg "Configurando pacotes de internet"
enable_internet_service
setting_iwd_on_networkmanager
msg "pacotes configurados com sucesso!"

