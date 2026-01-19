# Validation environnement for hardware security requirements

This repository contains tools and documentation for validation hardware
configuration of an x86 platform, and especially its security.

The goal is to facilitate security requirements verification, for example when
ordering PC platforms for the French administration.

The requirements themselves are published in a [separate
document](https://www.ssi.gouv.fr/en/guide/hardware-security-requirements-for-x86-platforms/)
(in [French](https://www.ssi.gouv.fr/guide/exigences-de-securite-materielles/)
as well)

Provided tools can be used to build a bootable USB key. This key can boot in
the following modes:

- the first is a Fedora live distribution including many tools which can be used
    to check the platform configuration registers, analyze the SPI flash
    content and collect information about the hardware.
- the second one is built around the `keytool.efi` binary which can be use to
    inspect and modify the _SecureBoot_ key list. The key can be used to check
    that the platform will accept new, custom _SecureBoot_ keys

## French Cybersecurity Agency (ANSSI)
<img src="https://www.sgdsn.gouv.fr/files/styles/ds_image_paragraphe/public/files/Notre_Organisation/logo_anssi.png" alt="ANSSI logo" width="30%">

![badge_repo](https://img.shields.io/badge/ANSSI--FR-chipsec--check-white)
[![category_badge_external](https://img.shields.io/badge/category-external-%23b556b6)](https://github.com/ANSSI-FR#types-de-projets)
[![openess_badge_C](https://img.shields.io/badge/code.gouv.fr-published-orange)](https://documentation.ouvert.numerique.gouv.fr/les-parcours-de-documentation/ouvrir-un-projet-num%C3%A9rique/#niveau-ouverture)

*This projet is managed by [ANSSI](https://cyber.gouv.fr/).To find out more, you can go to [page](https://cyber.gouv.fr/open-source-lanssi) dedicated to the ANSSI open source strategy. You can also click on the badges to learn more about their meaning*

## Cloning the repository

**BEWARE: this repository uses submodules!**

```
git clone --recurse-submodules https://github.com/ANSSI-FR/chipsec-check.git
```

See third-party/README.md for more tips working with submodules.

## Build requirements

- Fedora 41 is recommended, but any distribution with a recent-enough version of [systemd](https://github.com/systemd/systemd) and [mkosi](https://github.com/systemd/mkosi) should work.
- `dnf install mkosi distribution-gpg-keys xxd`

## Build and copy the image to USB key

```bash
# Generate Secure Boot keys - this is required only once
./gen_keys.sh
# Build the image
mkosi -i build
# Test the image in qemu
mkosi qemu
# Find the /dev device for the USB key
lsblk
# Burn the image to USB key /dev/sdX
# THIS WILL ERASE THE CONTENT OF YOUR KEY
mkosi burn /dev/sdX
# Or manually with dd:
sudo dd if=chipsec_check_0.1.raw of=/dev/sdX bs=4M status=progress
```

The USB key needs to be at least 4GB large.

## Usage

1. Disable Secure Boot
2. Boot from the USB key into Fedora
3. Run the following commands:

```bash
# If you want to skip the long tests
export FAST_MODE=1
dump_system
dump_bios
poweroff
```

4. Plug the key in another computer and analyse the results stored in the `/SRV` FAT-32 partition.

TODO:
- document how to install the testing key hierarchy instead of disabling Secure Boot.
- document analysis steps

## Tips

- Sometimes, mkosi builds get in a confused state and it helps to restart from a clean state. If you want to erase every build artifact and restart from scratch (**including the Secure Boot keys**), run: `git clean -ffdx`.
- To debug build issues: `mkosi -i --debug --debug-shell build`
- Do not run `mkosi build` as root, it will probably break the build. If you try to build from within a container, you may need mkosi version >= 25 to build without `sudo` (version 24 and below rely on uid mapping that is hard to get right in this context).

From the chipsec-check live distribution:
- To load a US QWERTY keyboard: `loadkeys us` (defaults to French)
- To stop annoying kernel messages in the console: `dmesg -n 1`
