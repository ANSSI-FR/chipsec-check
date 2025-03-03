#!/bin/bash
# vim: noexpandtab:
set -eE

usage () {
  cat <<EOF
NAME
	${0} - create a minimal linux system with ChipSec

SYNOPSIS
	${0} -d DISK [-r <repository] [-c <commit>] [-e "EXTRA PACKAGES"] [ -k "Path to keys folder" ]

DESCRIPTION
	Create a minimal linux system (with Chipsec installed) on DISK. DISK
	can be a block device or a file which can then be copied to a disk.
	The content of DISK is wiped by doing so, so be careful when using this tool.

	<repository> is the optional Chipsec git repository which will be cloned to
	DISK. If absent, official upstream from github is used.

	<commit> is the optional Chipsec commit ID or tag which will be checked out.
	If absent, master is used.

	"EXTRA_PACKAGES" is a quoted, space separated list of extra packages to
	install on the minimal Linux system.

	You can provide a path to the sets of keys to be used for Secure Boot
	signing. Default is to use the ca/ subfolder in the script source dir
	(following layout from upstream repository)
EOF
}

check_requirements () {
	local ret=0
	if [ ! -x /sbin/mkfs.vfat ];
	then
		echo "mkfs.vfat not found, please install the dosfstools package" >&2
		ret=1
	fi
	if [ ! -x /usr/bin/sbsign ];
	then
		echo "sbsign not found, please install the sbsigntool package" >&2
		ret=1
	fi
	if [ ! -f /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi ];
	then
		echo "KeyTool.efi not found, please install the efitools package" >&2
		ret=1
	fi
	if [ ! -f /usr/lib/efitools/x86_64-linux-gnu/HashTool.efi ];
	then
		echo "HashTool.efi not found, please install the efitools package" >&2
		ret=1
	fi
	if [ "$(id -u)" != 0 ];
	then
		echo "Please run as root or through sudo to create partitions on the target USB key" >&2
		ret=1
	fi
	return $ret
}

install_chipsec () {
	local repo=${repository:-https://github.com/chipsec/chipsec}
	if [ -n "$commit" ];
	then
		git clone -b "$commit" "${repo}" "${mount_point}/root/chipsec"
	else
		git clone "${repo}" "${mount_point}/root/chipsec"
	fi

	mkdir -p "${mount_point}"/root
	cp "$SRCDIR/build-chipsec.sh" "${mount_point}"/root/
	do_chroot /root/build-chipsec.sh

	rm "${mount_point}"/root/build-chipsec.sh
}

sign_grub () {
	local GRUB="${mount_point}/boot/EFI/debian/grubx64.efi"
	local BOOT="${mount_point}/boot/EFI/Boot/grubx64.efi"
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${BOOT}" "${GRUB}"
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${GRUB}" "${GRUB}"
}

sign_shim_boot () {
	local SHIM="${mount_point}/boot/EFI/debian/shimx64.efi"
	local BOOT="${mount_point}/boot/EFI/Boot/bootx64.efi"

	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${BOOT}" "${SHIM}"
}

sign_kernel () {
	for KERNEL in "${mount_point}"/boot/vmlinuz*;
	do
		sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${KERNEL}" "${KERNEL}"
	done

	# Also sign the Chipsec module
	local SIGNFILE=( "${mount_point}"/usr/lib/linux-kbuild-*/scripts/sign-file )
	${SIGNFILE[0]} sha256 "$keypath"/DB.key "$keypath"/DB.crt \
		"${mount_point}"/usr/local/lib/python*/dist-packages/chipsec-*/chipsec/helper/linux/chipsec.ko

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
		ask_confirm "${default}"
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

	sfdisk -q "${disk}" << EOF
label: gpt
size=256MiB,type=uefi,name=esp,bootable
size=3000MiB,type=linux,name=chipsec
type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7,name=data
EOF

	partprobe "${disk}"
	# Formatting an external device sometimes fails because the partition
	# table hasn't propagated (despite partprobe).
	# Printing the partition table seems to work around it.
	parted "${disk}" print
}

format_boot () {
	local boot=${1}

	mkfs.vfat -n ESP "${boot}"
}

format_data () {
	local data=${1}

	# Ensure FAT32 to allow partition resizing if a 2GB image is copied to
	# a larger USB key.
	mkfs.vfat -n DATA -F 32 "${data}"
}

format_root () {
	local root=${1}

	mkfs.ext4 -F "${root}"
}

mount_mnt () {
	local boot="${1}"
	local root="${2}"

	mount "${root}" "${mount_point}"
	mkdir -p "${mount_point}"/boot
	mount "${boot}" "${mount_point}"/boot
}

do_chroot () {
	PATH="$PATH:/usr/sbin:/sbin:/bin" chroot "${mount_point}"/ "$@"
}

install_debian () {
	local root="${1}"
	local boot="${2}"
	local data="${3}"

	debootstrap --variant=minbase stable "${mount_point}" https://deb.debian.org/debian/

	mount proc "${mount_point}"/proc -t proc
	mount sysfs "${mount_point}"/sys -t sysfs
	mount -o bind /dev "${mount_point}"/dev

	do_chroot apt -y install systemd linux-image-amd64 grub-efi iproute2
	do_chroot apt -y install build-essential linux-headers-amd64 pahole
	do_chroot apt -y install python3 python3-dev python3-setuptools
	do_chroot apt -y install vim-tiny sed nasm pciutils fwupd lshw usbutils
	do_chroot apt -y install tpm2-tools cpuid msr-tools dmidecode
	# Skip dpkg question about console-data configuration, we only care
	# about having a database for loadkeys.
	do_chroot sh -c "echo 'console-common	console-data/keymap/policy	select	Keep kernel keymap' | debconf-set-selections"
	do_chroot apt -y install kbd console-data

	if [ -n "${extra_packages}" ];
	then
		do_chroot apt -y install ${extra_packages}
	fi

	do_chroot apt clean

	echo chipsec > "${mount_point}"/etc/hostname
  
	echo "$(lsblk -n -o UUID -P "${root}")         /         ext4      defaults      1      1" > "${mount_point}"/etc/fstab
	echo "$(lsblk -n -o UUID -P "${boot}")         /boot     vfat      defaults      1      1" >> "${mount_point}"/etc/fstab
	echo "$(lsblk -n -o UUID -P "${data}")         /mnt/data vfat      defaults      1      1" >> "${mount_point}"/etc/fstab
	mkdir "${mount_point}"/mnt/data

	do_chroot update-grub
	do_chroot grub-install --target=x86_64-efi --efi-directory /boot --no-nvram
	do_chroot mkdir -p /boot/EFI/Boot
	do_chroot grub-mkconfig -o /boot/grub/grub.cfg
	do_chroot rm /boot/EFI/debian/BOOTX64.CSV

	do_chroot passwd -d root
}

install_ca () {
	mkdir -p "${mount_point}"/boot/EFI/keys
	cp "$keypath"/*.auth "$keypath"/*.esl "${mount_point}"/boot/EFI/keys/
}

install_shell () {
	local EFI="${mount_point}/boot/EFI/Boot/Shell.efi"

	mkdir -p "${EFI%/*}"
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${EFI}" "$SRCDIR/bin/Shell.efi"
}

install_keytool () {
	local KEFI="${mount_point}/boot/EFI/keytool/KeyTool.EFI"
	local HEFI="${mount_point}/boot/EFI/keytool/HelloWorld.EFI"

	mkdir -p "${KEFI%/*}"
	sbsign --key "$keypath"/DB.key --cert "$keypath"/DB.crt --output "${KEFI}" /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi

	cp /usr/lib/efitools/x86_64-linux-gnu/HashTool.efi "${HEFI}"
}


umount_debian () {
	umount "${mount_point}"/dev/
	umount "${mount_point}"/proc/
	umount "${mount_point}"/sys/
	umount "${mount_point}"/boot/
	umount "${mount_point}"
}

cleanup () {
	umount_debian
	rmdir "${mount_point}"
	if [ ! -b "$arg" ];
	then
		losetup -d "${disk}"
	fi
}

trap_cleanup () {
	set +E
	echo "Error in processus, cleaning up" >&2
	cleanup
}

main () {
	check_requirements || exit 1
	trap trap_cleanup ERR
	while getopts "c:d:e:k:r:" opt; do
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
			r)
				echo "Using repository ${OPTARG} for Chipsec"
				repository="${OPTARG}"
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

	printf "Use %s? It will be completely erased (Y/n) " "${arg}"
	exit_if_no "$(ask_confirm "Y")"

	if [ -b "${arg}" ]; #block device, just use it directly
	then
		disk=${arg}
		sep=""
	else
		truncate -s 4GB "${arg}"
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
	data="${disk}${sep}3"


	echo "Using ${boot} as boot partition"
	echo "Using ${root} as root partition"
	echo "Using ${data} as data partition"
	format_boot "${boot}"
	format_root "${root}"
	format_data "${data}"

	mount_mnt "${boot}" "${root}"

	install_ca
	install_shell
	install_keytool

	install_debian "${root}" "${boot}" "${data}"

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

	# Configure Grub boot entries
	echo "menuentry 'EFI Shell' { chainloader /EFI/Boot/Shell.efi }" >> "${mount_point}"/boot/grub/custom.cfg
	echo "menuentry 'Keytool' { chainloader /EFI/keytool/KeyTool.efi }" >> "${mount_point}"/boot/grub/custom.cfg

	cleanup
}

SRCDIR="$(dirname "$0")"
main "${@}"
