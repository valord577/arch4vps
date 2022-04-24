#!/usr/bin/env bash

# 1 enable | 0 disable
DEBUG_ON="0"

CURL_EXTRA_PARAMS=""
if [ "${DEBUG_ON}" == "0" ]; then
  CURL_EXTRA_PARAMS="-s"
fi

debug() {
  if [ "${DEBUG_ON}" == "0" ]; then
    return 0
  fi
  printf "\e[2m\e[36m%s\e[0m\n" "$@" >&2
}

abort() {
  printf "\e[4m\e[31m%s\e[0m\n" "$@" >&2
  exit 1
}

focus() {
  printf "\e[4m\e[32m%s\e[0m\n" "$@" >&2
}

prtln() {
  printf "%s\n" "$@" >&1
}

focus "This is the script to convert a VPS to Arch Linux."
prtln "."
prtln "."
prtln "."

# Check CPU arch
cpu_arch=$(uname -m)
debug "cpu_arch: ${cpu_arch}"
if [ "${cpu_arch}" != "x86_64" ]; then
  abort "Only x86_64 machines are supported."
fi

# Check commands
chk_cmds() {
  cmd=${1}
  tip=${2}

  if command -v ${cmd} >/dev/null 2>&1; then
    prtln "Checking command: ${cmd} ... ok!"
  else
    abort "Required command: ${cmd} ... ${tip}"
  fi
}

chk_cmds "curl" "Please install 'curl'."
chk_cmds "arch-chroot" "Please install 'arch-install-scripts'."

arch_chroot_exec() {
  arch-chroot "/root.${cpu_arch}" /bin/bash -c "${*}"
}

prtln "..."
# Confirm the root block name
ROOT_BLK="/dev/vda"
prtln "By default, the root block at:"
prtln "  > ${ROOT_BLK}"
focus "Which block is the root directory mounted to?"
read -p "  > (if empty, use default): " ROOT_BLK_IN
if [ "${ROOT_BLK_IN}" != "" ]; then
  ROOT_BLK=${ROOT_BLK_IN}
fi
debug "root block: ${ROOT_BLK}"

prtln "..."
# Confirm the mirror of arch linux
MIRROR="https://mirrors.bfsu.edu.cn/archlinux"
prtln "By default, use mirror:"
prtln "  > ${MIRROR}"
focus "What mirror would you like to use?"
read -p "  > (if empty, use default): " MIRROR_IN
if [ "${MIRROR_IN}" != "" ]; then
  MIRROR=${MIRROR_IN}
fi
debug "mirror url: ${MIRROR}"

prtln "..."
# Confirm the password for root
PASSWORD=""
focus "What password would you like to set for root?"
read -sp "  > (typing...): " PASSWORD_IN
while :
do
  if [ "${PASSWORD_IN}" != "" ]; then
    PASSWORD=${PASSWORD_IN}
    break
  else
    focus "The password seems to be blank."
    read -sp "  > (typing...): " PASSWORD_IN
  fi
done

prtln "" && cd /

prtln "..."
# Get archlinux bootstrap filename
sha1sums=$(curl ${CURL_EXTRA_PARAMS} --url "${MIRROR}/iso/latest/sha1sums.txt")
debug "sha1sums: "
debug "  >>>"
debug "${sha1sums}"
debug "  <<<"

arch_date_tgz=${sha1sums##*'archlinux-bootstrap-'}
BOOTSTRAP="archlinux-bootstrap-${arch_date_tgz}"
if [ "${arch_date_tgz##*${cpu_arch}}" != ".tar.gz" ]; then
  abort "Unknown bootstrap file: '${BOOTSTRAP}'"
fi
prtln "Bootstrap file: '${BOOTSTRAP}'"

prtln "..."
# Download bootstrap file and extract
curl ${CURL_EXTRA_PARAMS} --url "${MIRROR}/iso/latest/${BOOTSTRAP}" -o "${BOOTSTRAP}"
tar -zxp -f "${BOOTSTRAP}" -C "/"
# -- dns
cp -fL "/etc/resolv.conf" "/root.${cpu_arch}/etc"
# -- mirror
echo -e "\nServer = ${MIRROR}/\$repo/os/\$arch" >> "/root.${cpu_arch}/etc/pacman.d/mirrorlist"
# -- locale
echo -e "en_US.UTF-8 UTF-8" >> "/root.${cpu_arch}/etc/locale.gen"
echo -e "LC_ALL=en_US.UTF-8" > "/root.${cpu_arch}/etc/locale.conf"
# -- hostname
cp -fL "/etc/hostname" "/root.${cpu_arch}/etc"
# -- localtime
cp -fd "/etc/localtime" "/root.${cpu_arch}/etc"
# -- mount
mount --bind "/" "/root.${cpu_arch}/mnt"

prtln "..."
# Installing arch files and packages
arch_chroot_exec "locale-gen"
# -- pacman
arch_chroot_exec "pacman-key --init && pacman-key --populate archlinux"
# -- fstab backup
arch_chroot_exec "genfstab -U /mnt >> /etc/fstab"
# -- mtab
cp -fL --remove-destination "/etc/mtab" "/root.${cpu_arch}/etc/mtab"
# -- delete
ls -d -- /* | grep -v "\(dev\|proc\|sys\|root.${cpu_arch}\|run\)" | xargs rm -rf
# -- packages
/root.${cpu_arch}/usr/lib/ld-*.so.2 --library-path "/root.${cpu_arch}/usr/lib" \
  /root.${cpu_arch}/usr/bin/chroot "/root.${cpu_arch}" pacstrap -M /mnt base linux linux-firmware grub vim openssh
# -- dns
cp -fL "/root.${cpu_arch}/etc/resolv.conf" "/etc"
# -- locale
echo -e "en_US.UTF-8 UTF-8" >> "/etc/locale.gen"
echo -e "LC_ALL=en_US.UTF-8" > "/etc/locale.conf"
locale-gen
# -- fstab restore
cp -fL "/root.${cpu_arch}/etc/fstab" "/etc"
# -- hostname
cp -fL "/root.${cpu_arch}/etc/hostname" "/etc"
# -- localtime
cp -fd "/root.${cpu_arch}/etc/localtime" "/etc"
# -- password
echo -n "root:${PASSWORD}" | chpasswd
# -- grub install
grub-install --target=i386-pc --recheck --force "${ROOT_BLK}"
grub-mkconfig -o "/boot/grub/grub.cfg"
# -- dhcp
cat > '/etc/systemd/network/en.network' <<-'EOF'
[Match]
Name=en*

[Network]
DHCP=yes
DNSSEC=no
EOF

cat > '/etc/systemd/network/eth.network' <<-'EOF'
[Match]
Name=eth*

[Network]
DHCP=yes
DNSSEC=no
EOF
# -- sshd
sed -i '/^#PermitRootLogin/c PermitRootLogin yes' /etc/ssh/sshd_config
# -- systemd
systemctl enable systemd-networkd
systemctl enable sshd

# Finalize
prtln "."
prtln "."
prtln "."
focus "Your VM has been reimaged with Arch Linux."
focus "Then, you should reboot your VM manually."
