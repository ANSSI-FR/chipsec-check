#!/bin/bash
echo "Lancement des commandes sur :"
export marque=$1
export modele=$2
if [ -z "$marque" ]  
then 
	echo "Usage: $0 MARQUE modele"
	exit
fi
if [ -z "$modele" ]
then
	echo "Usage: $0 MARQUE modele"
	exit
fi
export versionbios=$(dmidecode --type 0 | grep "Version:" | cut -d : -f 2 | tr -d " ") 
echo "Lancement des commandes sur $marque $modele avec version BIOS $versionbios"

cd mount
lshw > lshw-$marque$modele.txt
lsusb > lsusb-$marque$modele.txt
lspci > lspci-$marque$modele.txt
dmidecode > dmidecode-$marque$modele.txt
lscpu > lscpu-$marque$modele.txt
dmesg | egrep -i 'iommu|amd-vi|vt-d' > iommu-$marque$modele.txt

chipsec_main -i > chipsec-$marque$modele-v$versionbios.txt
chipsec_util spi dump spibios-$marque$modele-v$versionbios.bin
ls -lstrh
