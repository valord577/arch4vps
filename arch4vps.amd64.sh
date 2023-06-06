#!/usr/bin/env bash
set -e

# 1 enable | 0 disable
DEBUG_ENABLED=${DEBUG_ENABLED:-"0"}
debug() {
  if [ "${DEBUG_ENABLED}" == "0" ]; then
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

script_fname="$(basename ${BASH_SOURCE[0]})"
script_fpath="$(cd "$(dirname ${BASH_SOURCE[0]})"; pwd)"
debug "script location: ${script_fpath}/${script_fname}"
if [ "${script_fpath}" != "/" ]; then
  abort "The script must be located at '/'."
fi

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
prtln "" && prtln "..."

prtln "..."
# Download bootstrap file and extract
BOOTSTRAP="archlinux-bootstrap-x86_64.tar.gz"
curl -fsSL --url "${MIRROR}/iso/latest/${BOOTSTRAP}" -o "${BOOTSTRAP}"

arch_rootfs="archlinux-bootstrap-rootfs"
mkdir -p "/${arch_rootfs}" && tar -xp -f "${BOOTSTRAP}" -C "/${arch_rootfs}" --numeric-owner --strip-components=1
# -- mirror
echo -e "\nServer = ${MIRROR}/\$repo/os/\$arch" >> "/${arch_rootfs}/etc/pacman.d/mirrorlist"
# -- backup
cp -fL "/etc/resolv.conf" "/${arch_rootfs}/etc"
cp -fL "/etc/hostname" "/${arch_rootfs}/etc"
cp -fd "/etc/localtime" "/${arch_rootfs}/etc"
# -- mount
mount --bind "/" "/${arch_rootfs}/mnt"

prtln "..."
# Installing arch files and packages
arch_chroot_exec() {
 /${arch_rootfs}/usr/bin/arch-chroot "/${arch_rootfs}" /bin/bash -c "${*}"
}
echo -e "en_US.UTF-8 UTF-8" >> "/${arch_rootfs}/etc/locale.gen"
arch_chroot_exec "locale-gen"
echo -e "LANG=en_US.UTF-8" > "/${arch_rootfs}/etc/locale.conf"

/${arch_rootfs}/usr/bin/arch-chroot "/${arch_rootfs}" /bin/bash <<EOT
set -e

pacman-key --init && pacman-key --populate archlinux
genfstab -U /mnt >> /etc/fstab

find /mnt -maxdepth 1 \( \
  ! -name "${arch_rootfs}" \
  -and ! -name "${script_fname}" \
  -and ! -name "dev" \
  -and ! -name "proc" \
  -and ! -name "sys" \
  -and ! -name "run" \
  \) | grep -v "^/mnt$" | xargs rm -rf 2>/dev/null || true

pacstrap -M /mnt base linux linux-firmware grub vim openssh
EOT

# -- restore
cp -fL "/${arch_rootfs}/etc/fstab" "/etc"
cp -fL "/${arch_rootfs}/etc/resolv.conf" "/etc"
cp -fL "/${arch_rootfs}/etc/hostname" "/etc"
cp -fd "/${arch_rootfs}/etc/localtime" "/etc"
# -- locale
echo -e "en_US.UTF-8 UTF-8" >> "/etc/locale.gen" && locale-gen
echo -e "LANG=en_US.UTF-8" > "/etc/locale.conf"
# -- password
echo -n "root:${PASSWORD}" | chpasswd
# -- grub install
grub-install --target=i386-pc --recheck --force "${ROOT_BLK}"
grub-mkconfig -o "/boot/grub/grub.cfg"
# -- dhcp
cat > '/etc/systemd/network/all.network' <<-'EOF'
[Match]
Name=*

[Network]
DHCP=yes
DNSSEC=no
EOF
# -- sshd
sed -i '/^#PermitRootLogin/c PermitRootLogin yes' /etc/ssh/sshd_config
# -- systemd
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd

# Finalize
prtln "."
prtln "."
prtln "."
focus "Your VM has been reimaged with Arch Linux."
focus "Then, you should reboot your VM manually."
focus "If necessary, use \`reboot -f\` to force reboot."
