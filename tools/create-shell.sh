#!/bin/sh
set -e

check_requirements() {
	local ret=0
	if [ ! -x /sbin/parted ];
	then
		echo "parted not found, please install the parted package" >&2
		ret=1
	fi
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
	if [ $(id -u) != 0 ];
	then
		echo "Please run as root or through sudo to create partitions on the target USB key" >&2
		ret=1
	fi
	return $ret
}

part_disk () {
	disk="${1}"

	parted "${1}" --script mklabel gpt
	parted "${1}" --script mkpart ESP fat32 1MiB 100%
	parted "${1}" --script set 1 boot on
}

umount_key () {
	umount "${mount_point}"
}

install_ca () {
	mkdir "${mount_point}"/keytool
	cp ca/*.auth ca/*.esl "${mount_point}"/keytool
	mkdir "${mount_point}"/builtin
	cp ca/*.cer "${mount_point}"/builtin
}

install_shell () {
	EFI="${mount_point}/EFI/Boot/BOOTX64.EFI"
	mkdir -p "${mount_point}"/EFI/Boot/
	cp bin/Shell.efi "${EFI}.tmp"
	sbsign --key ca/DB.key --cert ca/DB.crt --output "${EFI}" "${EFI}.tmp"
	rm "${EFI}.tmp"
}

install_key_tool () {
	KEFI="${mount_point}/KeyTool.EFI"
	HEFI="${mount_point}/HelloWorld.EFI"

	cp /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi "${KEFI}.tmp"
	sbsign --key ca/DB.key --cert ca/DB.crt --output "${KEFI}" "${KEFI}.tmp"
	rm "${KEFI}.tmp"

	cp /usr/lib/efitools/x86_64-linux-gnu/HashTool.efi "${HEFI}"
}

cleanup() {
	umount_key
	rmdir "${mount_point}"
	if [ ! -b "$arg" ];
	then
		losetup -d $target
	fi
}


main () {
	check_requirements || exit 1
	trap cleanup ERR
	arg="${1}"
	if [ -b "${arg}" ]; #block device, just use it directly
	then
		target=${arg}
		sep=""
	else
		if [ ! -f "${arg}" ]; # not a regular file, create it manually
		then
			truncate -s 4M ${arg}
		fi
		target=$(losetup --find --show "$arg")
		sep="p"
	fi

	mount_point=$(mktemp -d -p "" efishellXXX)
	part_disk "${target}"
	sleep 1
	mkfs.vfat "${target}${sep}1"

	mount "${target}${sep}1" ${mount_point}
	install_ca
	install_shell
	install_key_tool

	cleanup
}

main "${1}"
