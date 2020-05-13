#!/bin/bash
set -e

usage () {
  cat <<EOF
NAME
	${0} - create a minimal linux system with ChipSec

SYNOPSIS
	${0} -d DISK [-c <commit>] [-e "EXTRA PACKAGES"]

DESCRIPTION
	Create a minimal linux system (with Chipsec installed) on DISK. DISK
	can be a block device or a file which can then be copied to a disk.
	The content of DISK is wiped by doing so, so be careful when using this tool.

	<commit> is the optional Chipsec commit ID or tag which will be cloned to
	DISK. If absent, master is used.

	"EXTRA_PACKAGES" is a quoted, space separated list of extra packages to
	install on the minimal Linux system.
EOF
}

install_chipsec () {
	if [ -n "$commit" ];
	then
		do_chroot git clone -b $commit https://github.com/chipsec/chipsec /root/chipsec
	else
		do_chroot git clone https://github.com/chipsec/chipsec /root/chipsec
	fi

	mkdir -p "${mount_point}"/root
	cp "$SRCDIR/build-chipsec.sh" "${mount_point}"/root/
	do_chroot /root/build-chipsec.sh

	rm "${mount_point}"/root/build-chipsec.sh
}

sign_grub () {
	GRUB="${mount_point}/boot/EFI/debian/grubx64.efi"
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output ${GRUB} ${GRUB}
}

sign_shim_boot () {
	SHIM="${mount_point}/boot/EFI/debian/shimx64.efi"
	BOOT="${mount_point}/boot/EFI/Boot/bootx64.efi"
	# Fallback binary with bootx64.csv config file
	FB="${mount_point}/boot/EFI/debian/fbx64.efi"
	CFG="${mount_point}/boot/EFI/debian/BOOTX64.csv"
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output ${SHIM} ${SHIM}
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output ${BOOT} ${FB}
	echo "shimx64.efi,chipsec,,Start Chipsec Debian distribution" |iconv -t UCS-2 > ${CFG}
}

sign_kernel () {
	KERNEL="${mount_point}/boot/vmlinuz*"
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output ${KERNEL} ${KERNEL}
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

do_chroot() {
	PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ $*
}

install_debian () {
	root="${1}"
	boot="${2}"

	debootstrap stable "${mount_point}" https://deb.debian.org/debian/

	mount proc "${mount_point}"/proc -t proc
	mount sysfs "${mount_point}"/sys -t sysfs
	mount -o bind /dev "${mount_point}"/dev

	do_chroot apt -y install systemd linux-image-amd64 grub-efi
	do_chroot apt -y install git build-essential linux-headers-amd64
	do_chroot apt -y install python3 python3-dev python3-setuptools
	do_chroot apt -y install sed nasm pciutils fwupd lshw usbutils
	do_chroot apt -y install tpm2-tools

	if [ -n "${extra_packages}" ];
	then
		do_chroot apt -y install "${extra_packages}"
	fi

	echo chipsec > ${mount_point}/etc/hostname
  
	echo "UUID=$(get_uuid ${root})         /         ext4      defaults      1      1" > "${mount_point}"/etc/fstab
	echo "UUID=$(get_uuid ${boot})         /boot     vfat      defaults      1      1" >> "${mount_point}"/etc/fstab

	do_chroot update-grub
	do_chroot grub-install --target=x86_64-efi --efi-directory /boot --no-nvram
	do_chroot mkdir -p /boot/EFI/Boot
	do_chroot grub-mkconfig -o /boot/grub/grub.cfg

	do_chroot passwd -d root
}

install_ca () {
	mkdir -p "${mount_point}"/boot/EFI/keys
	cp "$SRCDIR"/ca/*.auth "$SRCDIR"/ca/*.esl "${mount_point}"/boot/EFI/keys/
}

install_shell () {
	EFI="${mount_point}/boot/EFI/Boot/Shell.efi"
	CFG="${mount_point}/boot/EFI/Boot/BOOTX64.csv"
	mkdir -p ${EFI%/*}
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output "${EFI}" "$SRCDIR/bin/Shell.efi"
	echo "Shell.efi,shell,,Start the UEFI shell" |iconv -t UCS-2 > ${CFG}
}

install_keytool () {
	KEFI="${mount_point}/boot/EFI/keytool/KeyTool.EFI"
	HEFI="${mount_point}/boot/EFI/keytool/HelloWorld.EFI"
	CFG="${mount_point}/boot/EFI/keytool/BOOTX64.csv"

	mkdir -p ${KEFI%/*}
	sbsign --key "$SRCDIR/ca/DB.key" --cert "$SRCDIR/ca/DB.crt" --output "${KEFI}" /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi

	cp /usr/lib/efitools/x86_64-linux-gnu/HashTool.efi "${HEFI}"
	echo "KeyTool.efi,keytool,,Start Secureboot keys management tool" |iconv -t UCS-2 > ${CFG}
}


umount_debian () {
	umount "${mount_point}"/dev/
	umount "${mount_point}"/proc/
	umount "${mount_point}"/sys/
	umount "${mount_point}"/boot/
	umount "${mount_point}"
}

cleanup() {
	set +e
	echo "Error in processus, cleaning up" >&2
	umount_debian
	losetup -d ${disk} 2>/dev/null
}

main () {
	while getopts "c:d:e:" opt; do
		case $opt in
			c)
				echo "Chipsec commit: ${OPTARG}"
				commit=${OPTARG}
				;;
			d)
				echo "Destination: ${OPTARG}"
				arg=${OPTARG}
				;;
			e)
				echo "Extra packages to install: ${OPTARG}"
				extra_packages="${OPTARG}"
				;;
			*)
				usage
				;;
		esac
	done
	if [ -z "${arg}" ];
	then
		usage
		exit 1
	fi
	trap cleanup ERR


	printf "Use ${arg}? It will be completely erased (Y/n) "
	exit_if_no "$(ask_confirm "Y")"

	if [ -b "${arg}" ]; #block device, just use it directly
	then
		disk=${arg}
		sep=""
	else
		truncate -s 2GB ${arg}
		disk=$(losetup --find --show "$arg")
		sep="p"
	fi

	mount_point=$(mktemp -d -p "" efiliveXXX)

	part_disk "${disk}"

	boot="${disk}${sep}1"
	root="${disk}${sep}2"


	echo "Using ${root} as root partition"
	echo "Using ${boot} as boot partition"
	format_boot "${boot}"
	format_root "${root}"

	mount_mnt "${boot}" "${root}"

	install_ca
	install_shell
	install_keytool

	install_debian "${root}" "${boot}"

	# Sign the boot entries with our own custom SecureBoot keys
	sign_grub
	sign_shim_boot
	sign_kernel

	install_chipsec

	# Install the dump_system script if possible
	if [ -f "$SRCDIR/dump_system.sh" ];
	then
		cp "$SRCDIR/dump_system.sh" "${mount_point}/root/"
	fi

	umount_debian

	rmdir ${mount_point}

	if [ ! -b "$arg" ];
	then
		losetup -d $disk
	fi
}

SRCDIR="$(dirname $0)"
main "${@}"
