#!/bin/bash

#usb key 1 (live usb debian) > ./create-keys.sh /dev/sdc -
#usb key 2 (shell.efi) > ./create-keys.sh - /dev/sdc

generate_keys () {
    cd ca
    ./gen.sh
    cd ..
}

main () {
    chipsec="${1}"
    shell="${2}"

    generate_keys

    if [ "${chipsec}" != "-" ]; then
        sudo ./create-chipsec.sh "${chipsec}"
    else
        echo "Skip chipsec"
    fi

    if [ "${shell}" != "-" ]; then
        sudo ./create-shell.sh "${shell}"
    else
        echo "Skip shell"
    fi
}

if [ $# != 2 ]; then
    echo "not enough argument"
    exit 1
fi

main "${1}" "${2}"
