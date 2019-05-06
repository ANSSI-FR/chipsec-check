#!/bin/sh

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

    cp bin/KeyTool.efi "${KEFI}.tmp"
    sbsign --key ca/DB.key --cert ca/DB.crt --output "${KEFI}" "${KEFI}.tmp"
    rm "${KEFI}.tmp"

    cp bin/HelloWorld.efi "${HEFI}"
}

main () {
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
