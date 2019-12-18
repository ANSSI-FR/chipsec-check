# Validation environnement for hardware security requirements

This repository contains tools and documentation for validation hardware
configuration of an x86 platform, and especially its security.

The goal is to facilitate security requirements verification, for example when
ordering PC platforms for the French administration.

The requirements themselves are published in a [separate
document](https://www.ssi.gouv.fr/en/guide/hardware-security-requirements-for-x86-platforms/)
(in [French](https://www.ssi.gouv.fr/guide/exigences-de-securite-materielles/)
as well)

Provided tools can be used to build two bootable USB keys:

- the first around the [chipsec](https://github.com/chipsec/chipsec) tool
	edited by Intel, integrated in a Debian live distribution, which can be used
	to check the platform configuration registers.
- the second one is built around the `keytool.efi` binary which can be use to
	inspect and modify the _SecureBoot_ key list. The key can be used to check
	that the platform will accept new, custom _SecureBoot_ keys

Documentation on what is tested with those tools are detailed in the
([doc/output](doc/output)) folder:

- [modules_chipsec.pdf](doc/output/modules_chipsec.pdf) explains the expected
	output from the chipsec tool
- [CPU Options.pdf](doc/output/CPU%20Options.pdf) details the security-related
	CPU options on Intel x86 platform
- [SPI Protection.pdf](doc/output/SPI%20Protection.pdf) details protection of
	the SPI flash hosting the BIOS code
- [SRAM Protection.pdf](doc/output/SRAM%20Protection.pdf) details register
	configuration for correct protection of the memory mapping (especially for
	SMRAM protection against SMM attacks)

The [documentation](doc) folder also provide guidance on how to build the USB
keys.
