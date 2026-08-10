# Current CAM-OV5645 investigation

Status: **validated on the inspected target**. The corrected OV5645 and
MX6S capture modules produce clean bounded captures and complete stream teardown
without the former target lockup.

## Direct target observations

On the inspected target (`5.15.71`), the sensor is `ov5645_camera_mipi_v2` at
I²C `3-003c`. `/dev/video1` is owned by the `mx6s-csi` platform driver from
`mx6s_capture.ko`; it is not driven by the installed but unloaded legacy
`mxc_v4l2_capture.ko` module. The loaded camera modules are
`mxc_mipi_csi.ko` and `ov5645_camera_mipi_v2.ko`.

The current boot DTB uses a 240 MHz MIPI CSI clock and `csis-wclk`. Its
SHA-256 is `2e7cdfd5b6af15b9e5bf25b7a7c247405eabddfdcaa3f0b77a66bfe62f80b9d1`.
A backup of this exact DTB is retained on the target boot partition as
`/imx7d-pico-pi.dtb.camera-investigation-baseline`.

## Confirmed control-plane mismatch

The V2 sensor driver programs its hardware mode from `VIDIOC_S_PARM`'s vendor
`capturemode` field, not from `VIDIOC_S_FMT`. Its `set_fmt` callback only
updates driver state. At probe the sensor is initialized at QSXGA. Therefore a
bare command such as `v4l2-ctl --set-fmt-video=width=1280,height=720,...`
configures the capture DMA for 1280×720 while the sensor remains at 2592×1944.

This was measured directly through I²C registers after that bare `S_FMT`:
`0x3808..0x380b` read `0x0a20 × 0x0798` (2592×1944). With the OV5645 internal
colour-bar test pattern enabled, the resulting 1280×720 image had diagonal,
wrapped bands. This explains the earlier green/black diagonal corruption; it
is not a YUYV-versus-UYVY interpretation issue.

A minimal V4L2 client that issued both requests corrected the sensor registers:

1. `VIDIOC_S_FMT`: YUYV, 1280×720;
2. `VIDIOC_S_PARM`: 30 fps and `capturemode = 2` (the driver's 720p mode).

The sensor then reported `0x0500 × 0x02d0` (1280×720). `v4l2-ctl` exposes
`--set-parm` for frame rate but not the vendor `capturemode`; in this driver it
selected mode 0 (640×480) rather than the requested 720p mode. Do not use a
bare `v4l2-ctl` format request as a camera-mode configuration procedure.

## Image-path evidence

With the explicitly synchronized 720p mode, one and then five OV5645 internal
colour-bar frames were clean. The five frames were byte-identical, delivered
at 30.00 fps, and showed the expected straight vertical bars. A separate
five-frame real-sensor capture reported 30.01 fps and had stable geometry with
no wrapping or corruption. That scene was very dark (mean luma 21–23/255), but
still contained consistent scene detail rather than the former diagonal
corruption.

The local raw captures and rendered contact sheets are deliberately ignored
under `artifacts/device-investigation/`; they are evidence for this inspected
target, not distributable image artifacts.

## Corrected drivers and validation

Two generated patches are applied only to a Git-free archive of the pinned
source commit during every module build:

- `ov5645-v4l2-mode-sync.patch` makes `S_FMT` own the selected mode, prevents
  the legacy `S_PARM.capturemode` input from replacing it, and initializes that
  mode at stream start.
- `mx6s-csi-stream-close.patch` stops a still-streaming downstream subdevice
  before the capture queue is released in the close path. It uses the 5.15
  `vb2_is_streaming()` API; a later TechNexion close-path patch used an API not
  present in this source tree.

The inspected target was updated with the rebuilt `ov5645_camera_mipi_v2.ko`
and `mx6s_capture.ko`, retaining module-file backups. A normal bare
`v4l2-ctl --set-fmt-video=width=1280,height=720,pixelformat=YUYV` capture then
programmed sensor registers `0x3808..0x380b` to `0x0500 × 0x02d0`.

Validation completed a 30-frame raw capture (55,296,000 bytes) and a 300-frame
10-second 1280×720 YUYV soak at 30 fps, including successful teardown and no
watchdog reset. The room was dark during real-scene tests, so those frames are
expectedly dark; the earlier wrapping/corruption was absent. The prebuilt
module set now contains all seven validated modules, including
`mx6s_capture.ko`.

The runtime 30-second watchdog and persistent journal storage remain installed
as investigation recovery measures; remove them deliberately if no longer
wanted.

## Receiver experiments

Three temporary DTB variants removed `csis-wclk` and respectively selected a
24 MHz, 240 MHz, or driver-default 166 MHz MIPI CSI clock. Each produced a
MIPI CSI `Frame Start` followed by `FIFO Overflow Error` and capture timeout.
The baseline 240 MHz + `csis-wclk` DTB was restored after the experiments.

## Next investigation boundary

The active `mx6s_capture` module is now part of the supported seven-module
set because its close-path fix was built against the pinned source, deployed,
and passed the target soak. Future image changes must retain the exact patch
replay, module identity validation, and bounded target capture check.
