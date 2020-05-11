#!/bin/sh

current_kernel () {
    #find /usr/lib/modules -maxdepth 2 -name build -type d
    find /lib/modules -maxdepth 2 -name build
}

cd /root/chipsec
KERNEL_SRC_DIR="$(current_kernel)" python3 setup.py install
