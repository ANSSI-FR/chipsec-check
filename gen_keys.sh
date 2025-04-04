#!/bin/bash -e
#
# SPDX-FileCopyrightText: 2025 ANSSI
# SPDX-License-Identifier: BSD-2-Clause
#
# Based on systemd's loader.conf man page.

rootdir=$(pwd)
dir=${1:-mkosi.extra/var/lib/sbctl}
mkdir -p "${dir}/keys"
cd "${dir}"

uuid=$(systemd-id128 new --uuid)
pki_name="chipsec-check secureboot test"

# No \n otherwise sbctl is not happy
printf "%s" "$uuid" > GUID

cd keys

for key in PK KEK db dbx; do
  # -nodes allows saving the private key without encryption (no passphrase)
  # https://serverfault.com/q/366372
  mkdir -p ${key}
  openssl req -new -x509 -nodes -subj "/CN=${pki_name} ${key}/" -keyout "${key}/${key}.key" -out "${key}/${key}.pem"
  openssl x509 -outform DER -in "${key}/${key}.pem" -out "${key}/${key}.der"
  sbsiglist --owner "${uuid}" --type x509 --output "${key}/${key}.esl" "${key}/${key}.der"
done

mkdir -p "MS"

# See also: <ulink url="https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/windows-secure-boot-key-creation-and-management-guidance">Windows Secure Boot Key Creation and Management Guidance</ulink>
curl -L "https://go.microsoft.com/fwlink/p/?linkid=321192" -o MS/ms-db-2011.der \
     -L "https://go.microsoft.com/fwlink/p/?linkid=321185" -o MS/ms-kek-2011.der \
     -L "https://go.microsoft.com/fwlink/p/?linkid=321194" -o MS/ms-uefi-db-2011.der \
     -L "https://go.microsoft.com/fwlink/p/?linkid=2239775" -o MS/ms-kek-2023.der \
     -L "https://go.microsoft.com/fwlink/p/?linkid=2239776" -o MS/ms-db-2023.der \
     -L "https://go.microsoft.com/fwlink/p/?linkid=2239872" -o MS/ms-uefi-db-2023.der
for key in MS/ms-*.der; do
  sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 --output "${key%der}esl" "${key}"
done
# Latest Microsoft DBX for x64, signed with Microsoft KEK
curl "https://uefi.org/sites/default/files/resources/x64_DBXUpdate.bin" --output "MS/ms-dbx.auth"


# Optionally add Microsoft Windows certificates (needed to boot into Windows).
cat MS/ms-db-*.esl >> db/db.esl

# Optionally add Microsoft UEFI certificates for firmware drivers / option ROMs and third-party
# boot loaders (including shim). This is highly recommended on real hardware as not including this
# may soft-brick your device (see next paragraph).
cat MS/ms-uefi-*.esl >> db/db.esl

# Optionally add Microsoft KEK certificates. Recommended if either of the Microsoft keys is used as
# the official UEFI revocation database is signed with this key. The revocation database can be
# updated with <citerefentry project='man-pages'><refentrytitle>fwupdmgr</refentrytitle><manvolnum>1</manvolnum></citerefentry>.
cat MS/ms-kek-*.esl >> KEK/KEK.esl

# Build a large DB/DBX (~60ko) : 1250 entries of hashes of an empty binary.
# Use a new random UUID for those.
"${rootdir}"/mkosi.extra/usr/local/bin/gen_db_esl 1250 db/large-db.esl
"${rootdir}"/mkosi.extra/usr/local/bin/gen_db_esl 1250 dbx/large-dbx.esl

attr=NON_VOLATILE,RUNTIME_ACCESS,BOOTSERVICE_ACCESS,TIME_BASED_AUTHENTICATED_WRITE_ACCESS
sbvarsign --attr ${attr} --key PK/PK.key --cert PK/PK.pem --output PK/PK.auth PK PK/PK.esl
sbvarsign --attr ${attr} --key PK/PK.key --cert PK/PK.pem --output KEK/KEK.auth KEK KEK/KEK.esl
sbvarsign --attr ${attr} --key KEK/KEK.key --cert KEK/KEK.pem --output db/db.auth db db/db.esl
sbvarsign --attr ${attr} --key KEK/KEK.key --cert KEK/KEK.pem --output dbx/dbx.auth dbx dbx/dbx.esl

sbvarsign --attr ${attr},APPEND_WRITE --key KEK/KEK.key --cert KEK/KEK.pem --output db/large-db.auth db db/large-db.esl
sbvarsign --attr ${attr},APPEND_WRITE --key KEK/KEK.key --cert KEK/KEK.pem --output dbx/large-dbx.auth dbx dbx/large-dbx.esl

rm -f -- */*.esl */*.der */*.base64
