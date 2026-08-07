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
