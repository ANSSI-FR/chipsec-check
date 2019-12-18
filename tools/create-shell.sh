#!/bin/sh
set -e

check_requirements() {
	local ret=0
	[ -x /sbin/parted ] || echo "parted not found, please install the parted package" >&2 && ret=1
	[ -x /sbin.mkfs.vfat ] || echo "mkfs.vfat not found, please install the dosfstools package" >&2 && ret=1
	[ -x /usr/bin/sbsign ] || echo "sbsign not found, please install the sbsigntool package" >&2 && ret=1
	[ -f /usr/lib/efitools/x86_64-linux-gnu/KeyTool.efi ] || echo "KeyTool.efi not found, please install the efitools package" >&2 && ret=1
	[ -f /usr/lib/efitools/x86_64-linux-gnu/HashTool.efi ] || echo "HashTool.efi not found, please install the efitools package" >&2 && ret=1
	return $ret
}

part_disk () {
    disk="${1}"

    parted "${1}" --script mklabel gpt
    parted "${1}" --script mkpart ESP fat32 1MiB 100%
    parted "${1}" --script set 1 boot on
}

format_key () {
    part="${1}"1
    sleep 1
    mkfs.vfat "${part}"
}

mount_key () {
    part="${1}"1
    mount "${part}" "${mount_point}"
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

main () {
		check_requirements || exit 1
    target="${1}"
    mount_point=$(mktemp -d -p "" efishellXXX)
    part_disk "${target}"
    format_key "${target}"

    mount_key "${target}"
    install_ca
    install_shell
    install_key_tool
    umount_key
    rmdir "${mount_point}"
}

main "${1}"
