#!/bin/bash
set -e

usage () {
  cat <<EOF
NAME
	${0} - create a minimal linux system with ChipSec

SYNOPSIS
	${0} -d DISK [-c <commit>] [-e "EXTRA PACKAGES"] [ -k "Path to keys folder" ]

DESCRIPTION
	Create a minimal linux system (with Chipsec installed) on DISK. DISK
	can be a block device or a file which can then be copied to a disk.
	The content of DISK is wiped by doing so, so be careful when using this tool.

	<commit> is the optional Chipsec commit ID or tag which will be cloned to
	DISK. If absent, master is used.

	"EXTRA_PACKAGES" is a quoted, space separated list of extra packages to
	install on the minimal Linux system.

	You can provide a path to the sets of keys to be used for Secure Boot
	signing. Default is to use the ca/ subfolder in the script source dir
	(following layout from upstream repository)
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
	local GRUB="${mount_point}/boot/EFI/debian/grubx64.efi"
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output ${GRUB} ${GRUB}
}

sign_shim_boot () {
	local SHIM="${mount_point}/boot/EFI/debian/shimx64.efi"
	local BOOT="${mount_point}/boot/EFI/Boot/bootx64.efi"
	# Fallback binary with bootx64.csv config file
	local FB="${mount_point}/boot/EFI/debian/fbx64.efi"
	local CFG="${mount_point}/boot/EFI/debian/BOOTX64.csv"

	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output ${SHIM} ${SHIM}
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output ${BOOT} ${FB}

	echo "shimx64.efi,chipsec,,Start Chipsec Debian distribution" |iconv -t UCS-2 > ${CFG}
}

sign_kernel () {
	local KERNEL="${mount_point}/boot/vmlinuz*"

	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output ${KERNEL} ${KERNEL}

	# Also sign the Chipsec module
	"${mount_point}"/usr/lib/linux-kbuild-4.19/scripts/sign-file \
		sha256 "$keypath"/DB.key "$keypath"/DB.crt \
		"${mount_point}"/usr/local/lib/python*/dist-packages/chipsec-*/chipsec/helper/linux/chipsec.ko
}


get_partuuid () {
	local disk="${1}"

	echo $(blkid ${disk} | sed 's/.*PARTUUID="\(.*\)".*/\1/')
}

get_uuid () {
	local disk="${1}"

	echo $(blkid ${disk} | sed 's/.* UUID="\(.*\)" T.*/\1/')
}

ask_confirm () {
	local c=""
	local default="${1}"

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
	local disk=${1}

	parted "${1}" --script mklabel gpt
	parted "${1}" --script mkpart ESP fat32 1MiB 100MiB
	parted "${1}" --script set 1 boot on
	parted "${1}" --script mkpart primary ext4 100MiB 100%
}

format_boot () {
	local boot=${1}

	sleep 1
	mkfs.vfat ${boot}
}


format_root () {
	local root=${1}

	sleep 1
	mkfs.ext4 -F ${root}
}

mount_mnt () {
	local boot="${1}"
	local root="${2}"

	mount ${root} "${mount_point}"
	mkdir -p "${mount_point}"/boot
	mount ${boot} "${mount_point}"/boot
}

do_chroot() {
	PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ $*
}

install_debian () {
	local root="${1}"
	local boot="${2}"

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
	cp "$keypath"/*.auth "$keypath"/*.esl "${mount_point}"/boot/EFI/keys/
}

install_shell () {
	local EFI="${mount_point}/boot/EFI/Boot/Shell.efi"
	local CFG="${mount_point}/boot/EFI/Boot/BOOTX64.csv"

	mkdir -p ${EFI%/*}
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${EFI}" "$SRCDIR/bin/Shell.efi"
	echo "Shell.efi,shell,,Start the UEFI shell" |iconv -t UCS-2 > ${CFG}
}

install_keytool () {
	local KEFI="${mount_point}/boot/EFI/keytool/KeyTool.EFI"
	local HEFI="${mount_point}/boot/EFI/keytool/HelloWorld.EFI"
	local CFG="${mount_point}/boot/EFI/keytool/BOOTX64.csv"

	mkdir -p ${KEFI%/*}
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${KEFI}" /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi

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
	while getopts "c:d:e:k:" opt; do
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
			k)
				echo "Path to keys: ${OPTARG}"
				keypath="${OPTARG}"
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

	if [ -z "${keypath}" ];
	then
		keypath="$SRCDIR"/ca
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

	install_chipsec

	# Install the dump_system script if possible
	if [ -f "$SRCDIR/dump_system.sh" ];
	then
		cp "$SRCDIR/dump_system.sh" "${mount_point}/root/"
	fi

	# Sign the boot entries with our own custom SecureBoot keys
	sign_grub
	sign_shim_boot
	sign_kernel

	echo -e "\n\nChipsec key built on $(date -R)" >> "${mount_point}"/etc/motd

	umount_debian

	rmdir ${mount_point}

	if [ ! -b "$arg" ];
	then
		losetup -d $disk
	fi
}

SRCDIR="$(dirname $0)"
main "${@}"
