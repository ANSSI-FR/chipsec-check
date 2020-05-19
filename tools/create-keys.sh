#!/bin/bash

#usb key 1 (live usb debian) > ./create-keys.sh live /dev/sdc
#usb key 2 (shell.efi) > ./create-keys.sh shell /dev/sdc

generate_keys () {
    ./gen-keys.sh
}

usage() {
    echo "Usage: $0 <live|shell> <device>" >&2
    exit 1
  }

main () {
    command=${1}
    device=${2}

    [ -f ca/myGUID.txt ] || generate_keys

    case "$command" in
      live)
        sudo ./create-chipsec.sh "${device}"
        ;;
      shell)
        sudo ./create-shell.sh "${device}"
        ;;
      *)
        usage
        ;;
    esac

}

if [ $# != 2 ]; then
    usage
fi

main "${1}" "${2}"
