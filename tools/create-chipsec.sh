#!/bin/bash

# Return this error code if the target is not present inside the file system
ENOTAFILE=1

usage () {
  cat <<EOF
NAME
        ${0} - create a minimal linux system with ChipSec

SYNOPSIS
        ${0} DISK

DESCRIPTION
        Create a minimal linux system (with Chipsec installed) on DISK. It wipes
        out the content of DISK by doing so, so be careful when using this tool.

ERRORS
        ENOTAFILE (1)
            DISK should be a file available inside a mounted filesystem, but it
            looks like it is not.
EOF
}

install_chipsec () {
  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}" git clone https://github.com/chipsec/chipsec /root/chipsec

  mkdir "${mount_point}"/root
  cp build-chipsec.sh "${mount_point}"/root/
  PATH="$PATH:/usr/sbin:/sbin:/bin"  chroot "${mount_point}" /root/build-chipsec.sh

  rm "${mount_point}"/root/build-chipsec.sh
}

sign_grub_boot () {
  EFI="${mount_point}/boot/EFI/Boot/BOOTX64.EFI"
  sbsign --key ca/DB.key --cert ca/DB.crt --output ${EFI}.signed ${EFI}
  mv ${EFI}.signed ${EFI}
}

get_partuuid () {
  disk="${1}"
  echo $(blkid ${disk} | sed 's/.*PARTUUID="\(.*\)".*/\1/')
}

get_uuid () {
  disk="${1}"
  echo $(blkid ${disk} | sed 's/.* UUID="\(.*\)" T.*/\1/')
}

ask_confirm () {
  c=""
  default="${1}"

  read -r -n1 c

  case ${c} in
    [yY] )
      echo "y"
      ;;
    [nN] )
      echo "n"
      ;;
    #TODO: fix that, as it is currently not working
    "\r" )
      echo "${default}"
      ;;
    *)
      printf "\nInvalid input, should be y(es) or n(o) "
      ask_confirm ${default}
      ;;
  esac
}

exit_if_no () {
  case ${1} in
    "n")
      exit 0
      ;;
  esac
}

part_disk () {
  disk=${1}

  parted "${1}" --script mklabel gpt
  parted "${1}" --script mkpart ESP fat32 1MiB 100MiB
  parted "${1}" --script set 1 boot on
  parted "${1}" --script mkpart primary ext4 100MiB 100%
}

format_boot () {
  boot=${1}
  sleep 1
  mkfs.vfat ${boot}
}

format_root () {
  root=${1}
  sleep 1
  mkfs.ext4 -F ${root}
}

mount_mnt () {
  boot="${1}"
  root="${2}"

  mount ${root} "${mount_point}"
  mkdir -p "${mount_point}"/boot
  mount ${boot} "${mount_point}"/boot
}

install_debian () {
  root="${1}"
  boot="${2}"

  debootstrap stable "${mount_point}" http://deb.debian.org/debian/

  mount proc "${mount_point}"/proc -t proc
  mount sysfs "${mount_point}"/sys -t sysfs
  mount -o bind /dev "${mount_point}"/dev

  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ apt install git systemd build-essential gcc make sed nasm python-setuptools linux-image-amd64 linux-headers-amd64 python python-dev grub-efi

  echo chipsec > ${mount_point}/etc/hostname
  
  echo "UUID=$(get_uuid ${root})         /         ext4      defaults      1      1" > "${mount_point}"/etc/fstab
  echo "UUID=$(get_uuid ${boot})         /boot     vfat      defaults      1      1" >> "${mount_point}"/etc/fstab

  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ update-grub
  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ grub-install --target=x86_64-efi --efi-directory /boot --no-nvram
  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ mkdir -p /boot/EFI/Boot
  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ cp /boot/EFI/debian/grubx64.efi /boot/EFI/Boot/BOOTX64.EFI
  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ grub-mkconfig -o /boot/EFI/grub/grub.cfg

  PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ passwd -d root
}

install_linux () {
  root="${1}"

  pacstrap "${mount_point}" bash coreutils systemd-sysvcompat kmod python2 udev filesystem linux-lts linux-lts-headers git gcc make sed nasm python2-setuptools
  arch-chroot "${mount_point}" bootctl --path /boot --no-variable install
  cat > "${mount_point}"/boot/loader/entries/mini.conf << EOF
title     Chipsec
linux     /vmlinuz-linux-lts
initrd    /initramfs-linux-lts.img
options   root=PARTUUID=$(get_partuuid ${root})
EOF

  genfstab -U "${mount_point}" >> "${mount_point}"/etc/fstab.tmp
  grep -v swap "${mount_point}"/etc/fstab.tmp > "${mount_point}"/etc/fstab
  rm "${mount_point}"/etc/fstab.tmp
}

unmount_linux () {
  umount "${mount_point}"/boot "${mount_point}"
}

umount_debian () {
  umount "${mount_point}"/dev/
  umount "${mount_point}"/proc/
  umount "${mount_point}"/sys/
  umount "${mount_point}"/boot/
  umount "${mount_point}"
}

main () {
  disk="${1}"
  mount_point=$(mktemp -d -p "" efiliveXXX)
  #if [[ ! -f "${disk}" ]]
  #then
  #  echo "${1} is not a file"
  #  exit ${ENOTAEFILE}
  #fi

  printf "Use ${disk}? (Y/n) "
  exit_if_no "$(ask_confirm "Y")"

  part_disk "${disk}"

  #boot="$(ls ${disk}* | egrep 1$)"
  #root=$(ls ${disk}* | egrep 2$)
  boot="${disk}"1
  root="${disk}"2
  sleep 1
  echo $root
  echo "${root} as root partition"
  echo "${boot} as boot partition"
  format_boot "${boot}"
  format_root "${root}"

  mount_mnt "${boot}" "${root}"

  install_debian "${root}" "${boot}"

  sign_grub_boot

  install_chipsec

  umount_debian

  rmdir ${mount_point}
}

main ${1}
