#!/bin/sh

current_kernel () {
    find /lib/modules -maxdepth 2 -name build
}

cd /root/chipsec
KSRC="$(current_kernel)" python3 setup.py build build_ext install
