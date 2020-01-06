#!/bin/bash
# Copyright (c) 2015 by Roderick W. Smith
# Licensed under the terms of the GPL v3

set -e

NAME="chipsec-sec secureboot test"

# efitools prior 1.9.2 has a bug preventing PK insertion in somes BIOSes
# See https://forums.lenovo.com/t5/ThinkPad-11e-Windows-13-E-and/Cannot-install-custom-secure-boot-PK-platform-key/td-p/4318378
# This bug manifests in sign-efi-sig-list so check that if possible
if [ -x /usr/bin/dpkg ];
then
	efitools_vers=$(sign-efi-sig-list --version | awk '{ print $2 }')
	if $(dpkg --compare-versions "$efitools_vers" lt "1.9.2");
	then
		echo "efitools version ($efitools_vers) is too old, please upgrade to efitools >= 1.9.2 to avoid potential bugs when inserting PK" >&2
		exit 1
	fi
fi

rm *.cer
rm *.crt
rm *.key
rm *.esl
rm *.auth

openssl req -new -x509 -newkey rsa:2048 -subj "/CN=$NAME PK/" -keyout PK.key \
        -out PK.crt -days 3650 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=$NAME KEK/" -keyout KEK.key \
        -out KEK.crt -days 3650 -nodes -sha256
openssl req -new -x509 -newkey rsa:2048 -subj "/CN=$NAME DB/" -keyout DB.key \
        -out DB.crt -days 3650 -nodes -sha256
openssl x509 -in PK.crt -out PK.cer -outform DER
openssl x509 -in KEK.crt -out KEK.cer -outform DER
openssl x509 -in DB.crt -out DB.cer -outform DER

GUID=`python2 -c 'import uuid; print str(uuid.uuid1())'`
echo $GUID > myGUID.txt

cert-to-efi-sig-list -g $GUID PK.crt PK.esl
cert-to-efi-sig-list -g $GUID KEK.crt KEK.esl
cert-to-efi-sig-list -g $GUID DB.crt DB.esl
rm -f noPK.esl
touch noPK.esl

sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" \
                  -k PK.key -c PK.crt PK PK.esl PK.auth
sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')" \
                  -k PK.key -c PK.crt PK noPK.esl noPK.auth
sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')"\
                  -k PK.key -c PK.crt KEK KEK.esl KEK.auth
sign-efi-sig-list -t "$(date --date='1 second' +'%Y-%m-%d %H:%M:%S')"\
       		  -k KEK.key -c KEK.crt db DB.esl DB.auth

chmod 0600 *.key

echo ""
echo ""
echo "For use with KeyTool, copy the *.auth and *.esl files to a FAT USB"
echo "flash drive or to your EFI System Partition (ESP)."
echo "For use with most UEFIs' built-in key managers, copy the *.cer files."
echo ""
