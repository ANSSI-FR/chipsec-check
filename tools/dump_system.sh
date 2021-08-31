#!/bin/bash
systemmanufacturer=$(dmidecode --string system-manufacturer | tr " " _)
systemversion=$(dmidecode --string system-version | tr " " _)
biosversion=$(dmidecode --string bios-version | tr " " _)
echo "Lancement des commandes sur ${systemmanufacturer} ${systemversion} avec version BIOS ${biosversion}"

if [ -z "$1" ];
then
	dir="${systemmanufacturer}_${systemversion}"
else
	dir="$1"
fi
mkdir -p "${dir}"
lshw > "${dir}/lshw.txt"
lsusb > "${dir}/lsusb.txt"
lspci -vvvnn > "${dir}/lspci.txt"
dmidecode -u > "${dir}/dmidecode.txt"
lscpu > "${dir}/lscpu.txt"
dmesg | grep -E -i 'iommu|amd-vi|vt-d' > "${dir}/iommu.txt"
fwupdmgr get-devices > "${dir}/fwupd.txt"
tpm2_getcap -c properties-fixed > "${dir}/tpm2.txt"

chipsec_main -i -k "${dir}/chipsec_v${biosversion}.md"
chipsec_util spi dump "${dir}/spibios_v${biosversion}.bin"
ls -lstrh "${dir}"
