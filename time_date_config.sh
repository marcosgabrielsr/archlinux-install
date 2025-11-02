set_timezone() {
    ln -sf /usr/share/zoneinfo/$TIMEZONE
}

synchronize_clock() {
    hwclock --systohc                               # sincroniza relógio da máquina com relógio do sistema
}

synchronize_internet_clock() {
    timedatectl set-ntp true                        # sincroniza o relógio local com o da internet
}