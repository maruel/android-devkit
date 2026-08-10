# Workflow status and authority

## Authority rules

The raw source notes are the provenance record. A source-note link means only
that the repository recorded the statement or command; it does not turn a
reported experiment into a verified result. External pages linked by the notes
are explicit follow-up references and were not contacted for this
documentation pass.

## Evidence-supported thread

The notes consistently use `MACHINE=pico-imx7` and `BASEBOARD=pi` for Yocto
commands, and describe the board as a Pico i.MX7D. [Yocto source note](source-notes/YOCTO.md)
[Ubuntu source note](source-notes/UBUNTU.md)

The Ubuntu source note records a downloadable `ubuntu-22.04.xz` under
TechNexion's `pico-imx7/pi-lcd800x480` image directory, followed by use of an
uncompressed `ubuntu-22.04` artifact in UUU. [Ubuntu source note](source-notes/UBUNTU.md)
[flashing source note](source-notes/FLASHING.md)

The Yocto source note records `imx-image-multimedia-pico-imx7.wic.bz2` and
`core-image-minimal-pico-imx7.sdcard.bz2` as build outputs, while another
recorded command targets `core-image-base`. These are alternatives, not a
single selected delivery image. [Yocto source note](source-notes/YOCTO.md)

## Blockers before an end-to-end workflow

- Select one exact base image and release. The notes mention Ubuntu 22.04,
  several Yocto releases, and several image names, without a verified chosen
  artifact.
- The physical Wi-Fi module is now confirmed: runtime SDIO ID `0x02d0:0x4335`
  resolves to BCM4339/2 in the vendor `brcmfmac` driver, and the BRCM DTB plus
  AP6335 firmware created `wlan0`. The earlier QCA selection in the downloaded
  image was incorrect for this device. [Ubuntu workflow](workflows/ubuntu.md)
- Confirm the running kernel release, its exact source tree/ref, and whether
  the recorded commit `9339d9595f0d5192cf154b6fe6b98f43e8226fe8` corresponds
  to the selected source/ref. The notes do not establish that mapping.
  [Ubuntu source note](source-notes/UBUNTU.md)
- Inspect the base image's kernel configuration and existing modules before
  choosing Wi-Fi or camera build settings. The source notes give a method for
  configuration extraction, but no captured configuration.
  [Ubuntu source note](source-notes/UBUNTU.md)
- Determine the boot-image/SPL/U-Boot pairing and artifact format for the
  selected release. The recorded self-built SPL path is explicitly marked as
  not working. [flashing source note](source-notes/FLASHING.md)
- Camera capture is validated. The target binds `ov5645_camera_mipi_v2` at
  `3-003c`; the tracked OV5645 mode-sync and MX6S stream-close fixes passed a
  300-frame target soak. See the [current camera
  investigation](camera-investigation.md).

## Prohibited assumptions

Do not infer partition layout, target USB path, boot media, kernel configuration,
or a successful build/flash from the notes. Runtime evidence supersedes the
earlier Wi-Fi ambiguity: this target requires `WIFI_MODULE=brcm` and the BRCM
device tree. [Ubuntu workflow](workflows/ubuntu.md)
