# Environnement de test des exigences matérielles

Ce dépôt contient des outils et la documentation permettant de vérifier la
configuration matérielle d'une plate-forme x86 et en particulier la sécurité de
celle-ci.

Le but de ce dépôt est de faciliter la vérification d'exigences de sécurité
matérielles, par exemple lors de la commande de plate-formes de type PC par
l'État français.

Les exigences elles-mêmes sont publiées dans un [document séparé]
(https://www.ssi.gouv.fr/guide/exigences-de-securite-materielles/) ([version
anglaise](https://www.ssi.gouv.fr/en/guide/hardware-security-requirements-for-x86-platforms/))

Les outils fournis permettent de construire une clé USB bootable qui peut être
démarrée dans l'un des deux modes suivants :

- le premier repose sur l'outil [chipsec](https://github.com/chipsec/chipsec)
	édité par Intel et qui permet l'inspection d'un certain nombre de registre de
	configuration.  Chipsec est intégré au sein d'une distribution Linux Debian.
- le second repose sur l'outil `keytool.efi` (fourni par le paquet `efitools`
	qui sert à inspecter et modifier la liste des clés utilisées dans le cadre de
	_SecureBoot_. Cette clé USB permet de valider que la plateforme peut être
	configurée avec des clés _SecureBoot_ personnalisées.

Des versions pré-construites des clés USB sont disponible sous forme d'ISO dans
la section [releases](https://github.com/ANSSI-FR/chipsec-check/releases). Les
executable EFI sont signés avec une clé généré par le développeur et ne
devraien être utilisées qu'à des fins d'évaluation. Les utilisateurs sont
fortement invités à générer leur propre autorité de certification et clés afin
d'utiliser celles ci pour des tests réels.
