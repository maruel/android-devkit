# Ubuntu image and kernel evidence

## Base image lead

The raw note records an Ubuntu 22.04 image download from TechNexion's
`pico-imx7/pi-lcd800x480` directory and decompression with `xz`; the flashing
note uses the resulting `ubuntu-22.04` name. Treat both as candidate inputs
until the exact release, checksum, and compatible boot assets are recorded.
[Ubuntu source note](../source-notes/UBUNTU.md)
[flashing source note](../source-notes/FLASHING.md)

## Kernel source and configuration extraction

The notes name the `TechNexion/linux-tn-imx` repository and two incompatible-
looking references: a repository branch URL for `tn-imx_5.15.71_2.2.0-stable`
and a checkout candidate `tn-kirkstone_5.15.71-2.2.2_20240220`. They also list
commit `9339d9595f0d5192cf154b6fe6b98f43e8226fe8`, but do not prove its
relationship to either reference. [Ubuntu source note](../source-notes/UBUNTU.md)

The recorded config-extraction method is to copy `/proc/config.gz` from the
running target, decompress it, and use it as `.config` in a cross-compiled ARM
kernel checkout. This is the required starting point for a compatible module
build, contingent on first recording the target's kernel release and the
source/ref mapping. [Ubuntu source note](../source-notes/UBUNTU.md)

## Reproducible extraction from the recorded Ubuntu 22.04 image

For one TechNexion Pico i.MX7 Ubuntu 22.04 image that has been inspected, the
VFAT partition's `/dev/sda1:/zImage` file has SHA-256
`5dc157521db63d3ba5223fd9680f5336b0da012b392454b7fc6b5e60de7e9756`. Its
zImage contains an LZOP stream beginning at byte 17,384. Decompressing that
stream and running the canonical Linux v5.15.71 `scripts/extract-ikconfig`
recovers a 188,691-byte configuration with SHA-256
`7f2c4ccf19a61c80bd43c3e9b85d64d43d7f97bd915a1cb9fcf56c92ad593825`.

`scripts/extract-pico-imx7-ubuntu-config.sh` implements only that observed
format. It does not mount an image, modify it, download anything, or claim to
support arbitrary ARM zImages. First obtain `/zImage` from the image by a
separate read-only method, and use a canonical `extract-ikconfig` from a Linux
source checkout matching the target kernel version:

```bash
scripts/extract-pico-imx7-ubuntu-config.sh \
  --zimage /absolute/path/to/zImage \
  --extract-ikconfig /absolute/path/to/linux-v5.15.71/scripts/extract-ikconfig \
  --output /absolute/path/to/output/pico-imx7-ubuntu-22.04.config \
  --expected-zimage-sha 5dc157521db63d3ba5223fd9680f5336b0da012b392454b7fc6b5e60de7e9756 \
  --expected-config-sha 7f2c4ccf19a61c80bd43c3e9b85d64d43d7f97bd915a1cb9fcf56c92ad593825
```

Prerequisites are local `dd`, `lzop`, `mktemp`, `sha256sum`, `grep`, `ln`, and
the supplied canonical extractor. The helper requires absolute, non-symlink
regular-file inputs and an existing non-symlink output parent. It refuses both
an existing config and its sibling `.provenance` record, stages all extraction
under a private temporary directory, validates both IKCONFIG settings, and
atomically publishes new paths without replacing any existing file.

The repository tracks the successful image extraction as
[`configs/pico-imx7/ubuntu-22.04-5.15.71.config`](../../configs/pico-imx7/ubuntu-22.04-5.15.71.config).
It also tracks a separately named, derived
[`ubuntu-22.04-5.15.71-prepared.config`](../../configs/pico-imx7/ubuntu-22.04-5.15.71-prepared.config)
for the exact vendor-source preflight. Read the
[configuration provenance](../../configs/pico-imx7/README.md) before using the
derived file: it is not byte-identical to the image configuration.

## Constrained module rebuild

For the selected QCA and MIPI OV5640 components, use the concrete builder only
with a local Git repository that contains TechNexion `linux-tn-imx` commit
`9339d9595f0d5192cf154b6fe6b98f43e8226fe8` and the derived configuration:

```bash
scripts/build-pico-imx7-ubuntu-modules.sh \
  --source-checkout /absolute/path/to/linux-tn-imx \
  --prepared-config /absolute/path/to/ubuntu-22.04-5.15.71-prepared.config \
  --output-dir /absolute/path/to/new-module-build-output
```

The command creates a Git-free source archive under its new output directory,
uses `/usr/bin/arm-linux-gnueabi-gcc-12`, performs a full kernel build to obtain
`Module.symvers`, then rebuilds only the required Wi-Fi and camera directories.
GCC 14 cannot complete this vendor kernel's `libahci` compilation, so it is not
a compatible substitute. The command publishes no image and installs nothing.
It rejects the result unless all
seven ARM modules are non-empty and their literal `.modinfo` vermagic matches
the inspected image:

- `ath.ko`, `ath10k_core.ko`, and `ath10k_pci.ko`;
- `mxc_v4l2_capture.ko`, `v4l2-int-device.ko`, `mxc_mipi_csi.ko`, and
  `ov5640_camera_mipi_v2.ko`.

The expected visible vermagic is
`5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8`; the raw module string
has one final spacer after `p2v8`, which the helper compares as well. A passing
vermagic check alone does not authorize image replacement: compare modversion
CRCs with the image module metadata when that metadata is available.

## Create the flash image

After a successful constrained module rebuild, create a new SD-card raw image
without modifying the downloaded base image:

```bash
scripts/create-pico-imx7-ubuntu-image.sh \
  --base-image /absolute/path/to/ubuntu-22.04.raw \
  --module-build /absolute/path/to/validated-module-build \
  --output-image /absolute/path/to/new-pico-imx7-ubuntu.raw
```

The helper verifies the exact inspected base-image checksum, expected two
partition layout, module build identity, ARM ELF type, and literal vermagic.
It copies the base image, replaces only the seven existing Wi-Fi/camera module
paths in the ext4 root filesystem, runs `depmod` against a private extracted
module tree, and verifies each copied module from the resulting image. It
writes a sibling `.provenance` record and refuses to overwrite either output.
Use the existing `flash-bundle.sh` only when separately validated SPL, U-Boot,
and UUU assets are available; this raw image is ready for a reviewed SD-card
flash workflow, not evidence that UUU boot assets are compatible.

Flash the raw image to a whole, unmounted SD-card block device only after the
default dry run prints both required confirmations:

```bash
scripts/flash-pico-imx7-ubuntu-image.sh \
  --image /absolute/path/to/new-pico-imx7-ubuntu.raw \
  --device /dev/sdX
```

The helper refuses partitions, mounted disks, the current root device, images
larger than the disk, a missing provenance record, or a checksum mismatch. It
does not write unless `--flash` and the exact image/device confirmations from
the dry run are supplied. Confirm the selected `/dev/sdX` independently: a
successful write is not a boot or hardware-function test.

## Wi-Fi module evidence

The notes record building `drivers/net/wireless/broadcom/brcm80211` after
enabling `brcmfmac` as a module, and copying `brcmfmac.ko` and `brcmutil.ko` to
the target followed by `depmod` and `modprobe`. They also record an HT-clock
timeout, so this is not proof of a working driver. [Ubuntu source note](../source-notes/UBUNTU.md)

The note links AP6335 firmware and a Buildroot NVRAM file, but it does not
establish the correct firmware/NVRAM filenames for the selected hardware.
Resolve that from the selected device tree, driver logs, and image before
installing firmware. [Ubuntu source note](../source-notes/UBUNTU.md)

## Camera evidence

The note identifies the CAM-OV5645 as a hardware claim and records V4L2 test
commands, a TechNexion camera-test link, and a question whether
`ov5640_camera_mipi_v2.ko` exists on a `5.15.71` target. It explicitly says
camera testing is not working. Therefore no camera build command is approved
yet. [Ubuntu source note](../source-notes/UBUNTU.md)

Before implementation, Phase 2 must obtain the target config, identify the
camera device-tree node and required media modules, and define a non-destructive
capture/format-enumeration acceptance test.
