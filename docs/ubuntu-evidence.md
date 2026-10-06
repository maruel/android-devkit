# Ubuntu build identities

This reference defines the identities used by the supported Ubuntu 22.04
workflow. It describes one inspected raw image; it does not generalize to other
Pico releases or arbitrary ARM kernels.

## Base image and kernel

- Raw image SHA-256:
  `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`.
- Target kernel: `5.15.71`.
- TechNexion `linux-tn-imx` source commit:
  `9339d9595f0d5192cf154b6fe6b98f43e8226fe8`.
- Required visible module vermagic:
  `5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8` (the literal module
  value includes one final space).

`./fetch-base-image.sh` and `./make-image.sh` are the normal wrappers. The
image-creation script refuses an incorrect base hash, unvalidated module set,
firmware, device tree, image contents, or provenance record. It also stages the
tracked low-memory policy into every new root filesystem, verifies its files and
service masks, and records policy-file hashes in provenance.
The shared policy configures a plain Xfce desktop, hardware-derived hostname,
root-owned device initialization, Ubuntu audio/video/render group membership,
Cheese 1280×720 defaults, conditional unused dnsmasq masking, bounded persistent
journaling, and a 30-second watchdog. Live verification checks PID 1 owns the
watchdog.

## Configuration provenance

The image's `/zImage` SHA-256 is
`5dc157521db63d3ba5223fd9680f5336b0da012b392454b7fc6b5e60de7e9756`. Its
observed LZOP stream begins at byte 17,384. Canonical Linux v5.15.71
`extract-ikconfig` recovers the authoritative 188,691-byte configuration:

- [`ubuntu-22.04-5.15.71.config`](../configs/pico-imx7/ubuntu-22.04-5.15.71.config),
  SHA-256 `7f2c4ccf19a61c80bd43c3e9b85d64d43d7f97bd915a1cb9fcf56c92ad593825`;
- [`ubuntu-22.04-5.15.71-prepared.config`](../configs/pico-imx7/ubuntu-22.04-5.15.71-prepared.config),
  the separately named derived source-build input, SHA-256
  `36d36040492a62bd7593cdc03311c7d7e7f65bac1ba1e40272f26cb278365b99`.

Read [configuration provenance](../configs/pico-imx7/README.md) before
using either file. The authoritative extraction is immutable; the builder uses
the derived file because vendor-source `olddefconfig` requirements differ.

## Rebuilding modules

`./build-drivers.sh` defaults to `/usr/bin/arm-linux-gnueabi-gcc-12` and accepts
an explicit absolute `--cross-gcc` path after verifying GCC 12 and the ARM EABI
target; GCC 14 does not build this vendor tree. It stages a Git-free archive at the pinned commit,
performs the required kernel build, applies the strict camera patches, and
produces a validated seven-module set. It checks ARM ELF type and the literal
vermagic and records the compiler, DTS and all three camera-patch identities.
Publishing a replacement requires current source attestations and two successful
finite camera acceptances using that build. Legacy v1 records remain readable
but cannot satisfy the publication requirements.

The supported set is recorded in
[`prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record`](../prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record):
`brcmutil.ko`, `brcmfmac.ko`, `mx6s_capture.ko`, `mxc_v4l2_capture.ko`,
`v4l2-int-device.ko`, `mxc_mipi_csi.ko`, and `ov5645_camera_mipi_v2.ko`.

## Wi-Fi and boot files

Runtime SDIO identity `0x02d0:0x4335` identifies the AP6335 radio as Broadcom
BCM4339/2. The image creator installs the BRCM device tree
(`imx7d-pico-pi.dtb`) and exact AP6335 firmware
and NVRAM aliases, with `wifi_module=brcm` in `uEnv.txt`, to provide `wlan0`.

## Flashing boundary

The UUU assets are fetched separately with `./fetch-emmc-boot-assets.sh` and
are required by the default `./flash-emmc.sh` invocation. The root
[flash guide](../README.md) is the authoritative operator procedure:
maintain its USB-device check, jumper positions, dry-run default, and explicit
flash confirmation. Use the maintained flashing scripts.
