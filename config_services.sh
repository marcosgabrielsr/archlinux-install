# Habilita os serviços NetworkManager e iwd para iniciarem junto com o sistema
enable_internet_service() {
    systemctl enable NetworkManager iwd
}

# Configura o iwd como sistema de conecção para o NetworkManager
setting_iwd_on_networkmanager() {
    CONFIG_PATH="/etc/NetworkManager/NetworkManager.conf"
    echo "[device]" >> $CONFIG_PATH
    echo "wifi.backend=iwd" >> $CONFIG_PATH
}