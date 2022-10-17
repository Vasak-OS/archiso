#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="vasakos"
iso_label="VasakOS_$(date +%Y%m)"
iso_publisher="VasakOS <https://os.vasak.net.ar/>"
iso_application="VasakOS Live"
iso_version="$(date +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
bootmodes=('bios.syslinux.mbr' 'bios.syslinux.eltorito' 'uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/lightdm"]="0:0:755"
  ["/etc/lightdm/lightdm.conf"]="0:0:755"
  ["/etc/sudoers.d"]="0:0:755"
  ["/etc/sudoers.d/g_wheel"]="0:0:400"
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/etc/os-release"]="0:0:777"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/share/applications/"]="0:0:755"
  ["/usr/share/applications/browser.desktop"]="0:0:755"
)
