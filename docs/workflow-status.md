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
- Confirm the physical module and its Wi-Fi package. The Ubuntu note contains
  contradictory QCA9377 and AP6335/BCM4339 descriptions; the investigation
  calls AP6335/BCM4339 a conclusion from internet sources, not hardware
  evidence. [Ubuntu source note](source-notes/UBUNTU.md)
  [investigation source note](source-notes/INVESTIGATION.md)
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
- Establish a camera acceptance test and the required driver/module set. The
  note says camera testing is not working and only questions whether
  `ov5640_camera_mipi_v2.ko` is present. [Ubuntu source note](source-notes/UBUNTU.md)

## Prohibited assumptions

Do not infer partition layout, device credentials, target USB path, boot media,
kernel configuration, firmware filename, or a successful build/flash from the
notes. In particular, do not make `WIFI_MODULE=brcm` a solution: the notes
record it as ineffective in at least one Yocto attempt. [Yocto source note](source-notes/YOCTO.md)
[investigation source note](source-notes/INVESTIGATION.md)
