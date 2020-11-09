#!/bin/bash

set -eu

_err() {
    printf 'Error: %s.\n' "$1" 1>&2
    exit 1
}

_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

late_command=
_late_command() {
    [ -z "$late_command" ] && late_command='true'
    late_command="$late_command; $1"
}

_prompt_password() {
    if [ -z "$password" ]; then
        read -rs -p 'Password: ' password
    fi
}

ip=
netmask=
gateway=
dns='8.8.8.8 8.8.4.4'
hostname=
installer_ssh=false
installer_password=
authorized_keys_url=
suite=buster
mirror_protocol=http
mirror_host=deb.debian.org
mirror_directory=/debian
security_repository=http://security.debian.org/debian-security
skip_account_setup=false
username=debian
password=
cleartext_password=false
timezone=UTC
ntp=0.debian.pool.ntp.org
skip_partitioning=false
partitioning_method=regular
disk=
gpt=false
efi=false
filesystem=ext4
kernel=
install_recommends=true
install=
upgrade=
kernel_params=
bbr=false
power_off=false
architecture=
boot_directory=/boot/
dry_run=false

while [ $# -gt 0 ]; do
    case $1 in
        --preset)
            case "$2" in
                china)
                    dns='223.5.5.5 223.6.6.6'
                    mirror_protocol=https
                    mirror_host=mirrors.aliyun.com
                    ntp=ntp.aliyun.com
                    security_repository=true
                    ;;
                cloud)
                    dns='1.1.1.1 1.0.0.1'
                    mirror_protocol=https
                    mirror_host=deb.debian.org
                    security_repository=true
                    ;;
                *)
                    _err "No such preset $2"
            esac
            shift
            ;;
        --ip)
            ip=$2
            shift
            ;;
        --netmask)
            netmask=$2
            shift
            ;;
        --gateway)
            gateway=$2
            shift
            ;;
        --dns)
            dns=$2
            shift
            ;;
        --hostname)
            hostname=$2
            shift
            ;;
        --installer-password)
            installer_ssh=true
            installer_password=$2
            shift
            ;;
        --authorized-keys-url)
            installer_ssh=true
            authorized_keys_url=$2
            shift
            ;;
        --suite)
            suite=$2
            shift
            ;;
        --mirror-protocol)
            mirror_protocol=$2
            shift
            ;;
        --mirror-host)
            mirror_host=$2
            shift
            ;;
        --mirror-directory)
            mirror_directory=${2%/}
            shift
            ;;
        --security-repository)
            security_repository=$2
            shift
            ;;
        --skip-account-setup)
            skip_account_setup=true
            ;;
        --username)
            username=$2
            shift
            ;;
        --password)
            password=$2
            shift
            ;;
        --timezone)
            timezone=$2
            shift
            ;;
        --ntp)
            ntp=$2
            shift
            ;;
        --skip-partitioning)
            skip_partitioning=true
            ;;
        --partitioning-method)
            partitioning_method=$2
            shift
            ;;
        --disk)
            disk=$2
            shift
            ;;
        --gpt)
            gpt=true
            ;;
        --efi)
            efi=true
            ;;
        --filesystem)
            filesystem=$2
            shift
            ;;
        --kernel)
            kernel=$2
            shift
            ;;
        --cloud-kernel)
            kernel=linux-image-cloud-amd64
            ;;
        --no-install-recommends)
            install_recommends=false
            ;;
        --install)
            install=$2
            shift
            ;;
        --safe-upgrade)
            upgrade=safe-upgrade
            ;;
        --full-upgrade)
            upgrade=full-upgrade
            ;;
        --eth)
            kernel_params=' net.ifnames=0 biosdevname=0'
            ;;
        --bbr)
            bbr=true
            ;;
        --power-off)
            power_off=true
            ;;
        --architecture)
            architecture=$2
            shift
            ;;
        --boot-partition)
            boot_directory=/
            ;;
        --dry-run)
            dry_run=true
            ;;
        *)
            _err "Illegal option $1"
    esac
    shift
done

installer="debian-$suite"
installer_directory="/boot/$installer"

save_preseed='cat'
if [ "$dry_run" != true ]; then
    user="$(id -un 2>/dev/null || true)"

    [ "$user" != root ] && _err 'root privilege is required'

    rm -rf "$installer_directory"
    mkdir -p "$installer_directory"
    cd "$installer_directory"
    save_preseed='tee -a preseed.cfg'
fi

$save_preseed << 'EOF'
# Localization

d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

# Network configuration

d-i netcfg/choose_interface select auto
EOF

if [ -n "$ip" ]; then
    echo 'd-i netcfg/disable_autoconfig boolean true' | $save_preseed
    echo "d-i netcfg/get_ipaddress string $ip" | $save_preseed
    [ -n "$netmask" ] && echo "d-i netcfg/get_netmask string $netmask" | $save_preseed
    [ -n "$gateway" ] && echo "d-i netcfg/get_gateway string $gateway" | $save_preseed
    [ -n "$dns" ] && echo "d-i netcfg/get_nameservers string $dns" | $save_preseed
    echo 'd-i netcfg/confirm_static boolean true' | $save_preseed
fi

$save_preseed << 'EOF'
d-i netcfg/get_hostname string debian
d-i netcfg/get_domain string
EOF

if [ -n "$hostname" ]; then
    echo "d-i netcfg/hostname string $hostname" | $save_preseed
fi

echo 'd-i hw-detect/load_firmware boolean true' | $save_preseed

if [ "$installer_ssh" = true ]; then
    $save_preseed << 'EOF'

# Network console

d-i anna/choose_modules string network-console
d-i preseed/early_command string anna-install network-console
EOF

    if [ -n "$authorized_keys_url" ]; then
        _late_command 'sed -ri "s/^#?PasswordAuthentication .+/PasswordAuthentication no/" /etc/ssh/sshd_config'
        $save_preseed << EOF
d-i network-console/password-disabled boolean true
d-i network-console/authorized_keys_url string $authorized_keys_url
EOF
    elif [ -n "$installer_password" ]; then
        $save_preseed << EOF
d-i network-console/password-disabled boolean false
d-i network-console/password password $installer_password
d-i network-console/password-again password $installer_password
EOF
    fi

    echo 'd-i network-console/start select Continue' | $save_preseed
fi

$save_preseed << EOF

# Mirror settings

d-i mirror/country string manual
d-i mirror/protocol string $mirror_protocol
d-i mirror/$mirror_protocol/hostname string $mirror_host
d-i mirror/$mirror_protocol/directory string $mirror_directory
d-i mirror/$mirror_protocol/proxy string
d-i mirror/suite string $suite
d-i mirror/udeb/suite string $suite
EOF

if [ "$skip_account_setup" != true ]; then
    if _command_exists mkpasswd; then
        if [ -z "$password" ]; then
            password="$(mkpasswd -m sha-512)"
        else
            password="$(mkpasswd -m sha-512 "$password")"
        fi
    elif _command_exists busybox && busybox mkpasswd --help >/dev/null 2>&1; then
        _prompt_password
        password="$(busybox mkpasswd -m sha512 "$password")"
    elif _command_exists python3; then
        if [ -z "$password" ]; then
            password="$(python3 -c 'import crypt, getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))')"
        else
            password="$(python3 -c "import crypt; print(crypt.crypt(\"$password\", crypt.mksalt(crypt.METHOD_SHA512)))")"
        fi
    else
        cleartext_password=true
        _prompt_password
    fi

    $save_preseed << 'EOF'

# Account setup

EOF

    if [ "$username" = root ]; then
        if [ -z "$authorized_keys_url" ]; then
            _late_command 'sed -ri "s/^#?PermitRootLogin .+/PermitRootLogin yes/" /etc/ssh/sshd_config'
        else
            _late_command "mkdir -pm 700 /root/.ssh && busybox wget -qO /root/.ssh/authorized_keys \"$authorized_keys_url\""
        fi

        $save_preseed << 'EOF'
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
EOF

        if [ "$cleartext_password" = true ]; then
            $save_preseed << EOF
d-i passwd/root-password password $password
d-i passwd/root-password-again password $password
EOF
        else
            echo "d-i passwd/root-password-crypted password $password" | $save_preseed
        fi
    else
        _late_command 'sed -ri "s/^#?PermitRootLogin .+/PermitRootLogin no/" /etc/ssh/sshd_config'

        if [ -n "$authorized_keys_url" ]; then
            _late_command "sudo -u $username mkdir -pm 700 /home/$username/.ssh && sudo -u $username busybox wget -qO /home/$username/.ssh/authorized_keys \"$authorized_keys_url\""
        fi

        $save_preseed << EOF
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string
d-i passwd/username string $username
EOF

        if [ "$cleartext_password" = true ]; then
            $save_preseed << EOF
d-i passwd/user-password password $password
d-i passwd/user-password-again password $password
EOF
        else
            echo "d-i passwd/user-password-crypted password $password" | $save_preseed
        fi
    fi
fi

$save_preseed << EOF

# Clock and time zone setup

d-i time/zone string $timezone
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true
d-i clock-setup/ntp-server string $ntp
EOF

if [ "$skip_partitioning" != true ]; then
    $save_preseed << 'EOF'

# Partitioning

EOF
    if [ -n "$disk" ]; then
        echo "d-i partman-auto/disk string $disk" | $save_preseed
    fi

    echo "d-i partman-auto/method string $partitioning_method" | $save_preseed

    if [ "$partitioning_method" = regular ]; then

        [ "$gpt" = true ] && $save_preseed << 'EOF'
d-i partman-partitioning/default_label string gpt
EOF

        echo "d-i partman/default_filesystem string $filesystem" | $save_preseed

        $save_preseed << 'EOF'
d-i partman-auto/expert_recipe string \
    naive :: \
EOF
        if [ "$efi" = true ]; then
            $save_preseed << 'EOF'
        538 538 1075 free \
            $iflabel{ gpt } \
            $reusemethod{ } \
            method{ efi } \
            format{ } \
        . \
EOF
        else
            $save_preseed << 'EOF'
        1 1 1 free \
            $iflabel{ gpt } \
            $reusemethod{ } \
            method{ biosgrub } \
        . \
EOF
        fi

        $save_preseed << 'EOF'
        2149 2150 -1 $default_filesystem \
            method{ format } \
            format{ } \
            use_filesystem{ } \
            $default_filesystem{ } \
            mountpoint{ / } \
        .
EOF
        echo "d-i partman-auto/choose_recipe select naive" | $save_preseed
    fi

    $save_preseed << 'EOF'
d-i partman-basicfilesystems/no_swap boolean false
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
EOF

fi

$save_preseed << 'EOF'

# Base system installation

EOF

[ "$install_recommends" = false ] && echo "d-i base-installer/install-recommends boolean $install_recommends" | $save_preseed
[ -n "$kernel" ] && echo "d-i base-installer/kernel/image string $kernel" | $save_preseed

[ "$security_repository" = true ] && security_repository=$mirror_protocol://$mirror_host${mirror_directory%/*}/debian-security

$save_preseed << EOF

# Apt setup

d-i apt-setup/services-select multiselect updates, backports
d-i apt-setup/local0/repository string $security_repository $suite/updates main
d-i apt-setup/local0/source boolean true
EOF

$save_preseed << 'EOF'

# Package selection

tasksel tasksel/first multiselect ssh-server
EOF

[ -n "$install" ] && echo "d-i pkgsel/include string $install" | $save_preseed
[ -n "$upgrade" ] && echo "d-i pkgsel/upgrade select $upgrade" | $save_preseed

$save_preseed << 'EOF'
popularity-contest popularity-contest/participate boolean false

# Boot loader installation

d-i grub-installer/bootdev string default
EOF

[ -n "$kernel_params" ] && echo "d-i debian-installer/add-kernel-opts string$kernel_params" | $save_preseed

$save_preseed << 'EOF'

# Finishing up the installation

d-i finish-install/reboot_in_progress note
EOF

[ "$bbr" = true ] && _late_command '{ echo "net.core.default_qdisc=fq"; echo "net.ipv4.tcp_congestion_control=bbr"; } > /etc/sysctl.d/bbr.conf'

[ -n "$late_command" ] && echo "d-i preseed/late_command string in-target sh -c '$late_command'" | $save_preseed

[ "$power_off" = true ] && echo 'd-i debian-installer/exit/poweroff boolean true' | $save_preseed

save_grub_cfg='cat'
if [ "$dry_run" != true ]; then
    [ -z "$architecture" ] && architecture=amd64 && _command_exists dpkg && architecture="$(dpkg --print-architecture)"

    base_url="$mirror_protocol://$mirror_host$mirror_directory/dists/$suite/main/installer-$architecture/current/images/netboot/debian-installer/$architecture"

    if _command_exists wget; then
        wget "$base_url/linux" "$base_url/initrd.gz"
    elif _command_exists curl; then
        curl -O "$base_url/linux" -O "$base_url/initrd.gz"
    elif _command_exists busybox; then
        busybox wget "$base_url/linux" "$base_url/initrd.gz"
    else
        _err 'wget/curl/busybox is required to download files'
    fi

    gunzip initrd.gz
    echo preseed.cfg | cpio -H newc -o -A -F initrd
    gzip initrd

    if _command_exists update-grub; then
        grub_cfg=/boot/grub/grub.cfg
        update-grub
    elif _command_exists grub2-mkconfig; then
        grub_cfg=/boot/grub2/grub.cfg
        grub2-mkconfig -o "$grub_cfg"
    else
        _err 'update-grub/grub2-mkconfig command not found'
    fi

    save_grub_cfg="tee -a $grub_cfg"
fi

installer_directory="$boot_directory$installer"

$save_grub_cfg << EOF
menuentry 'Debian Installer' --id debi {
    insmod part_msdos
    insmod part_gpt
    insmod ext2
    linux $installer_directory/linux$kernel_params
    initrd $installer_directory/initrd.gz
}
EOF
