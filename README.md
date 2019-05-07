# Validation environement for hardware security requirements

This repository contains tools and documentatoin for validation hardware
configuration of an x86 platform, and especially its security.

The goal is to facilitate security requirements verification, for example when
ordering PC platforms for the French administration.

Provided tools can be used to build two bootable USB keys:

- the first around the [chipsec](https://github.com/chipsec/chipsec) tool
  edited by Intel, integrated in a Debian live distribution, which can be used
	to check the platform configuration registers.
- the second one is built around the `keytool.efi` binary which can be use to
  inspect and modify the _SecureBoot_ key list. The key can be used to check
	that the platform will accept new, custom _SecureBoot_ keys
