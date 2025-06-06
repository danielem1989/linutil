#!/bin/bash

# Redirect stdout and stderr to archsetup.txt and still output to console
exec > >(tee -i archsetup.txt)
exec 2>&1

echo -ne "
-------------------------------------------------------------------------
 ██████╗  █████╗ ███╗   ██╗██╗███████╗██╗     ███████╗
 ██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██║     ██╔════╝
 ██║  ██║███████║██╔██╗ ██║██║█████╗  ██║     █████╗  
 ██║  ██║██╔══██║██║╚██╗██║██║██╔══╝  ██║     ██╔══╝  
 ██████╔╝██║  ██║██║ ╚████║██║███████╗███████╗███████╗
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚══════╝
-------------------------------------------------------------------------
                Installazione Automatizzata di Arch Linux
-------------------------------------------------------------------------

Verifica che l'ISO di Arch Linux sia avviata

"
if [ ! -f /usr/bin/pacstrap ]; then
    echo "Questo script deve essere eseguito da un ambiente ISO di Arch Linux."
    exit 1
fi

root_check() {
    if [[ "$(id -u)" != "0" ]]; then
        echo -ne "ERRORE! Questo script deve essere eseguito con l'utente 'root'!\n"
        exit 0
    fi
}

docker_check() {
    if awk -F/ '$2 == "docker"' /proc/self/cgroup | read -r; then
        echo -ne "ERRORE! Il container Docker non è supportato (al momento)\n"
        exit 0
    elif [[ -f /.dockerenv ]]; then
        echo -ne "ERRORE! Il container Docker non è supportato (al momento)\n"
        exit 0
    fi
}

arch_check() {
    if [[ ! -e /etc/arch-release ]]; then
        echo -ne "ERRORE! Questo script deve essere eseguito in Arch Linux!\n"
        exit 0
    fi
}

pacman_check() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        echo "ERRORE! Pacman è bloccato."
        echo -ne "Se non è in esecuzione rimuovi /var/lib/pacman/db.lck.\n"
        exit 0
    fi
}

background_checks() {
    root_check
    arch_check
    pacman_check
    docker_check
}

# @description Displays DANIELE logo
# @noargs
logo () {
# This will be shown on every set as user is progressing
echo -ne "
-------------------------------------------------------------------------
 ██████╗  █████╗ ███╗   ██╗██╗███████╗██╗     ███████╗
 ██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██║     ██╔════╝
 ██║  ██║███████║██╔██╗ ██║██║█████╗  ██║     █████╗  
 ██║  ██║██╔══██║██║╚██╗██║██║██╔══╝  ██║     ██╔══╝  
 ██████╔╝██║  ██║██║ ╚████║██║███████╗███████╗███████╗
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚══════╝
------------------------------------------------------------------------
     Seleziona le impostazioni di preconfigurazione per il tuo sistema
------------------------------------------------------------------------
"
}

# @description Disk selection for drive to be used with installation.
diskpart () {
echo -ne "
------------------------------------------------------------------------
    QUESTO FORMATTERÀ E CANCELLERÀ TUTTI I DATI SUL DISCO
    Assicurati di sapere cosa stai facendo perché
    dopo la formattazione del disco non c'è modo di recuperare i dati
    *****FAI UN BACKUP DEI TUOI DATI PRIMA DI CONTINUARE*****
    ***NON SONO RESPONSABILE PER EVENTUALI PERDITE DI DATI***
------------------------------------------------------------------------

"

    echo "Dischi disponibili:"
    # Create an array to store disk paths
    declare -a disks
    # Counter for disk numbering
    counter=1
    
    # Read disks into array and display numbered list
    while IFS= read -r line; do
        disks+=("$line")
        echo "$counter) $line"
        ((counter++))
    done < <(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" - "$3}')
    
    echo ""
    read -r -p "Seleziona il numero del disco su cui installare (es. 1): " disk_num
    
    # Validate input is a number
    if ! [[ "$disk_num" =~ ^[0-9]+$ ]]; then
        echo "Errore: Inserisci un numero valido"
        diskpart
        return
    fi
    
    # Check if the number is within valid range
    if [ "$disk_num" -lt 1 ] || [ "$disk_num" -gt "${#disks[@]}" ]; then
        echo "Errore: Selezione non valida. Scegli un numero tra 1 e ${#disks[@]}"
        diskpart
        return
    fi
    
    # Get the selected disk path (array is 0-indexed, user input is 1-indexed)
    disk=$(echo "${disks[$((disk_num-1))]}" | awk '{print $1}')
    
    if [ ! -b "$disk" ]; then
        echo "Errore: $disk non è un dispositivo a blocchi valido"
        diskpart
    else
        echo -e "\n$disk selezionato \n"
        export DISK=$disk
    fi
}

# @description Gather username and password to be used for installation.
userinfo () {
    # Loop through user input until the user gives a valid username
    while true
    do
            read -r -p "Inserisci il nome utente: " username
            if [[ "${username,,}" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]
            then
                    break
            fi
            echo "Nome utente non corretto."
    done
    export USERNAME=$username

    while true
    do
        read -rs -p "Inserisci la password: " PASSWORD1
        echo -ne "\n"
        read -rs -p "Reinserisci la password: " PASSWORD2
        echo -ne "\n"
        if [[ "$PASSWORD1" == "$PASSWORD2" ]]; then
            break
        else
            echo -ne "ERRORE! Le password non corrispondono. \n"
        fi
    done
    export PASSWORD=$PASSWORD1

     # Loop through user input until the user gives a valid hostname, but allow the user to force save
    while true
    do
            read -r -p "Inserisci il nome del computer: " name_of_machine
            # hostname regex (!!couldn't find spec for computer name!!)
            if [[ "${name_of_machine,,}" =~ ^[a-z][a-z0-9_.-]{0,62}[a-z0-9]$ ]]
            then
                    break
            fi
            # if validation fails allow the user to force saving of the hostname
            read -r -p "Il nome host non sembra corretto. Vuoi salvarlo comunque? (s/n)" force
            if [[ "${force,,}" = "s" ]]
            then
                    break
            fi
    done
    export NAME_OF_MACHINE=$name_of_machine
}

# Set automatic configurations
set_auto_config() {
    export FS=ext4
    export TIMEZONE="Europe/Rome"
    export KEYMAP="it"
    export MOUNT_OPTIONS="noatime,discard"
    echo -ne "
    Configurazioni automatiche impostate:
    - File System: ext4
    - Fuso orario: Europe/Rome
    - Layout tastiera: Italiano (it)
    - Disco ottimizzato per SSD
    "
}

# Starting functions
background_checks
clear
logo
userinfo
clear
logo
diskpart
clear
logo
set_auto_config

echo "Configurazione dei mirror per download ottimale"
iso=$(curl -4 ifconfig.co/country-iso)
timedatectl set-ntp true
pacman -Sy
pacman -S --noconfirm archlinux-keyring #update keyrings to latest to prevent packages failing to install
pacman -S --noconfirm --needed pacman-contrib terminus-font
setfont ter-v18b
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
pacman -S --noconfirm --needed reflector rsync grub
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
echo -ne "
-------------------------------------------------------------------------
         Configurazione dei mirror $iso per download più veloci
-------------------------------------------------------------------------
"
reflector -a 48 -c "$iso" -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist
if [ ! -d "/mnt" ]; then
    mkdir /mnt
fi
echo -ne "
-------------------------------------------------------------------------
                    Installazione Prerequisiti
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed gptfdisk btrfs-progs glibc
echo -ne "
-------------------------------------------------------------------------
                    Formattazione Disco
-------------------------------------------------------------------------
"
umount -A --recursive /mnt # make sure everything is unmounted before we start
# disk prep
sgdisk -Z "${DISK}" # zap all on disk
sgdisk -a 2048 -o "${DISK}" # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' "${DISK}" # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+1GiB --typecode=2:ef00 --change-name=2:'EFIBOOT' "${DISK}" # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' "${DISK}" # partition 3 (Root), default start, remaining
if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
    sgdisk -A 1:set:2 "${DISK}"
fi
partprobe "${DISK}" # reread partition table to ensure it is correct

# make filesystems
echo -ne "
-------------------------------------------------------------------------
                    Creazione Filesystem
-------------------------------------------------------------------------
"

if [[ "${DISK}" =~ "nvme" ]]; then
    partition2=${DISK}p2
    partition3=${DISK}p3
else
    partition2=${DISK}2
    partition3=${DISK}3
fi

mkfs.vfat -F32 -n "EFIBOOT" "${partition2}"
mkfs.ext4 "${partition3}"
mount -t ext4 "${partition3}" /mnt

BOOT_UUID=$(blkid -s UUID -o value "${partition2}")

sync
if ! mountpoint -q /mnt; then
    echo "ERRORE! Impossibile montare ${partition3} su /mnt dopo diversi tentativi."
    exit 1
fi
mkdir -p /mnt/boot/efi
mount -t vfat -U "${BOOT_UUID}" /mnt/boot/efi

if ! grep -qs '/mnt' /proc/mounts; then
    echo "Il disco non è montato, impossibile continuare"
    echo "Riavvio tra 3 secondi ..." && sleep 1
    echo "Riavvio tra 2 secondi ..." && sleep 1
    echo "Riavvio tra 1 secondo ..." && sleep 1
    reboot now
fi

echo -ne "
-------------------------------------------------------------------------
            Installazione di Arch sul Disco Principale
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    pacstrap /mnt base base-devel linux-lts linux-firmware --noconfirm --needed
else
    pacstrap /mnt base base-devel linux-lts linux-firmware efibootmgr --noconfirm --needed
fi
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

genfstab -U /mnt >> /mnt/etc/fstab
echo "
  Generato /etc/fstab:
"
cat /mnt/etc/fstab
echo -ne "
-------------------------------------------------------------------------
         Installazione e Controllo Bootloader GRUB BIOS
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot "${DISK}"
fi
echo -ne "
-------------------------------------------------------------------------
         Controllo per sistemi con poca memoria <8G
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -lt 8000000 ]]; then
    # Put swap into the actual system, not into RAM disk, otherwise there is no point in it, it'll cache RAM into RAM. So, /mnt/ everything.
    mkdir -p /mnt/opt/swap # make a dir that we can apply NOCOW to to make it btrfs-friendly.
    if findmnt -n -o FSTYPE /mnt | grep -q btrfs; then
        chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    fi
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    chmod 600 /mnt/opt/swap/swapfile # set permissions.
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile
    # The line below is written to /mnt/ but doesn't contain /mnt/, since it's just / for the system itself.
    echo "/opt/swap/swapfile    none    swap    sw    0    0" >> /mnt/etc/fstab # Add swap to fstab, so it KEEPS working after installation.
fi

gpu_type=$(lspci | grep -E "VGA|3D|Display")

arch-chroot /mnt /bin/bash -c "KEYMAP='${KEYMAP}' /bin/bash" <<EOF

echo -ne "
-------------------------------------------------------------------------
                    Configurazione Rete
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed networkmanager dhclient
systemctl enable --now NetworkManager
echo -ne "
-------------------------------------------------------------------------
         Configurazione dei mirror per download ottimale
-------------------------------------------------------------------------
"
pacman -S --noconfirm --needed pacman-contrib curl
pacman -S --noconfirm --needed reflector rsync grub arch-install-scripts git ntp wget
cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

nc=$(grep -c ^processor /proc/cpuinfo)
echo -ne "
-------------------------------------------------------------------------
                    Hai " $nc" core. E
         sto modificando i makeflags per " $nc" core. Così come
              le impostazioni di compressione.
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -gt 8000000 ]]; then
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi
echo -ne "
-------------------------------------------------------------------------
     Impostazione lingua Italiana e configurazione locale
-------------------------------------------------------------------------
"
sed -i 's/^#it_IT.UTF-8 UTF-8/it_IT.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
timedatectl --no-ask-password set-timezone ${TIMEZONE}
timedatectl --no-ask-password set-ntp 1
localectl --no-ask-password set-locale LANG="it_IT.UTF-8" LC_TIME="it_IT.UTF-8"
ln -s /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

# Set keymaps
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
echo "XKBLAYOUT=${KEYMAP}" >> /etc/vconsole.conf
echo "Layout tastiera impostato su: ${KEYMAP}"

# Add sudo no password rights
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

#Add parallel downloading
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

#Set colors and enable the easter egg
sed -i 's/^#Color/Color\nILoveCandy/' /etc/pacman.conf

#Enable multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm --needed

echo -ne "
-------------------------------------------------------------------------
                    Installazione Microcode
-------------------------------------------------------------------------
"
# determine processor type and install microcode
if grep -q "GenuineIntel" /proc/cpuinfo; then
    echo "Installazione microcode Intel"
    pacman -S --noconfirm --needed intel-ucode
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    echo "Installazione microcode AMD"
    pacman -S --noconfirm --needed amd-ucode
else
    echo "Impossibile determinare il produttore della CPU. Salto l'installazione del microcode."
fi

echo -ne "
-------------------------------------------------------------------------
                    Installazione Driver Grafici
-------------------------------------------------------------------------
"
# Graphics Drivers find and install
if echo "${gpu_type}" | grep -E "NVIDIA|GeForce"; then
    echo "Installazione driver NVIDIA: nvidia-lts"
    pacman -S --noconfirm --needed nvidia-lts
elif echo "${gpu_type}" | grep 'VGA' | grep -E "Radeon|AMD"; then
    echo "Installazione driver AMD: xf86-video-amdgpu"
    pacman -S --noconfirm --needed xf86-video-amdgpu
elif echo "${gpu_type}" | grep -E "Integrated Graphics Controller"; then
    echo "Installazione driver Intel:"
    pacman -S --noconfirm --needed libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
elif echo "${gpu_type}" | grep -E "Intel Corporation UHD"; then
    echo "Installazione driver Intel UHD:"
    pacman -S --noconfirm --needed libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
fi

echo -ne "
-------------------------------------------------------------------------
                    Aggiunta Utente
-------------------------------------------------------------------------
"
groupadd libvirt
useradd -m -G wheel,libvirt -s /bin/bash $USERNAME
echo "$USERNAME creato, directory home creata, aggiunto ai gruppi wheel e libvirt, shell predefinita impostata su /bin/bash"
echo "$USERNAME:$PASSWORD" | chpasswd
echo "Password di $USERNAME impostata"
echo $NAME_OF_MACHINE > /etc/hostname

echo -ne "
-------------------------------------------------------------------------
 ██████╗  █████╗ ███╗   ██╗██╗███████╗██╗     ███████╗
 ██╔══██╗██╔══██╗████╗  ██║██║██╔════╝██║     ██╔════╝
 ██║  ██║███████║██╔██╗ ██║██║█████╗  ██║     █████╗  
 ██║  ██║██╔══██║██║╚██╗██║██║██╔══╝  ██║     ██╔══╝  
 ██████╔╝██║  ██║██║ ╚████║██║███████╗███████╗███████╗
 ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚══════╝
-------------------------------------------------------------------------
                Installazione Automatizzata di Arch Linux
-------------------------------------------------------------------------

Configurazioni e Setup Finali
Installazione e Controllo Bootloader GRUB EFI
"

if [[ -d "/sys/firmware/efi" ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux --removable
fi

echo -ne "
-------------------------------------------------------------------------
          Creazione (e Personalizzazione) Menu di Boot Grub
-------------------------------------------------------------------------
"
# set kernel parameter for adding splash screen
sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& splash /' /etc/default/grub

echo -e "Installazione tema Grub CyberRe..."
THEME_DIR="/boot/grub/themes/CyberRe"
echo -e "Creazione directory del tema..."
mkdir -p "${THEME_DIR}"

# Clone the theme
cd "${THEME_DIR}" || exit
git init
git remote add -f origin https://github.com/ChrisTitusTech/Top-5-Bootloader-Themes.git
git config core.sparseCheckout true
echo "themes/CyberRe/*" >> .git/info/sparse-checkout
git pull origin main
mv themes/CyberRe/* .
rm -rf themes
rm -rf .git

echo "Il tema CyberRe è stato clonato in ${THEME_DIR}"
echo -e "Backup della configurazione Grub..."
cp -an /etc/default/grub /etc/default/grub.bak
echo -e "Impostazione del tema come predefinito..."
grep "GRUB_THEME=" /etc/default/grub 2>&1 >/dev/null && sed -i '/GRUB_THEME=/d' /etc/default/grub
echo "GRUB_THEME=\"${THEME_DIR}/theme.txt\"" >> /etc/default/grub
echo -e "Aggiornamento grub..."
grub-mkconfig -o /boot/grub/grub.cfg
echo -e "Tutto configurato!"

echo -ne "
-------------------------------------------------------------------------
                    Abilitazione Servizi Essenziali
-------------------------------------------------------------------------
"
ntpd -qg
systemctl enable ntpd.service
echo "  NTP abilitato"
systemctl disable dhcpcd.service
echo "  DHCP disabilitato"
systemctl stop dhcpcd.service
echo "  DHCP fermato"
systemctl enable NetworkManager.service
echo "  NetworkManager abilitato"

echo -ne "
-------------------------------------------------------------------------
                    Pulizia
-------------------------------------------------------------------------
"
# Remove no password sudo rights
sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
# Add sudo rights
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
EOF
