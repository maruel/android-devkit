# Pico i.MX7 Ubuntu 22.04 kernel configurations

This directory deliberately holds two different configuration snapshots. They
must not be treated as interchangeable.

`ubuntu-22.04-5.15.71.config` is the authoritative, byte-for-byte extraction
from the inspected image's `/zImage` IKCONFIG payload:

- SHA-256: `7f2c4ccf19a61c80bd43c3e9b85d64d43d7f97bd915a1cb9fcf56c92ad593825`
- Source compressed image SHA-256:
  `d23c04fe49b2537e5240f4b448f4d43f720d80ebb057d0bb62238a13b1a5b3ef`
- Source raw image SHA-256:
  `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`
- `/zImage` SHA-256:
  `5dc157521db63d3ba5223fd9680f5336b0da012b392454b7fc6b5e60de7e9756`
- Extraction: canonical Linux v5.15.71 `scripts/extract-ikconfig` after
  decompression of the observed LZOP stream at byte offset 17,384.

`ubuntu-22.04-5.15.71-prepared.config` is a derived build input, not an image
extraction. It was produced by `olddefconfig` from the authoritative file in a
Git-free archive of TechNexion `linux-tn-imx` commit
`9339d9595f0d5192cf154b6fe6b98f43e8226fe8`:

- SHA-256: `644090a71b5dbc975720d6e4fbdb391b9e8869064ac6fd6689a64c12965093dc`
- Source-alignment evidence:
  `artifacts/ubuntu-22.04/source-alignment-9339d959-report.txt` in the
  evidence workspace.
- The same derived output was produced by candidate commit
  `af4b4f3be385277f8d6f24e05c776d9339f0a556`.

Compared with the authoritative image configuration, the derived configuration
changes the selected QCA9377 transport from the image's unusable PCI module to
the matching SDIO module (`CONFIG_ATH10K_SDIO=m`,
`CONFIG_ATH10K_PCI` disabled), carries the Kconfig compiler-version baseline,
and adds
Kconfig defaults/capability values, including `CONFIG_VIDEO_TEVS=y`,
`CONFIG_CC_HAS_ASM_GOTO_OUTPUT=y`, auto-variable-initialization capability
flags, zero-call-used-register capability flags, and
`CONFIG_HAVE_KCSAN_COMPILER=y`. `CONFIG_VIDEO_TEVS` is present with `default y`
in that vendor source's `drivers/media/i2c/Kconfig`.

The build script runs `olddefconfig` with its pinned GCC 12 cross-compiler, so
the resulting build configuration records that compiler's actual version.

The expected visible image module vermagic is
`5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8`. The literal raw
`.modinfo` value has one final spacer after `p2v8`; a build must match that
byte as well. Matching the release alone is insufficient.
