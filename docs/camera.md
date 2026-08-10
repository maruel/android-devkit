# CAM-OV5645 camera validation

Status: **validated on the inspected target**. The corrected OV5645 and MX6S
capture modules produce clean bounded captures and complete stream teardown
without the former target lockup.

## Target and receiver

The target runs `5.15.71`; the CAM-OV5645 sensor is
`ov5645_camera_mipi_v2` at I²C `3-003c`. `/dev/video1` belongs to the
`mx6s-csi` platform driver in `mx6s_capture.ko`, not the installed but unloaded
legacy `mxc_v4l2_capture.ko`. The active sensor and receiver modules are
`ov5645_camera_mipi_v2.ko` and `mxc_mipi_csi.ko`.

The boot DTB has SHA-256
`2e7cdfd5b6af15b9e5bf25b7a7c247405eabddfdcaa3f0b77a66bfe62f80b9d1`. It uses
a 240 MHz MIPI CSI clock with `csis-wclk`; a target-side baseline backup is
`/imx7d-pico-pi.dtb.camera-investigation-baseline`. Three temporary variants
without `csis-wclk`, using 24 MHz, 240 MHz, or the driver default 166 MHz,
all produced a MIPI CSI frame start followed by FIFO overflow and timeout. Do
not change the baseline receiver settings.

## Corruption cause and fix

The V2 sensor driver's original `VIDIOC_S_FMT` callback updated only driver
state. Hardware mode was instead selected by the vendor `capturemode` field of
`VIDIOC_S_PARM`. Consequently a normal V4L2 client could configure DMA for
1280×720 while the probe-time QSXGA sensor mode remained 2592×1944. I²C
registers `0x3808..0x380b` confirmed that mismatch, and the OV5645 colour-bar
test pattern showed diagonal wrapped bands. This was not a YUYV/UYVY issue.

Two patches are replayed on a Git-free archive of the pinned kernel source for
each driver build:

- [`ov5645-v4l2-mode-sync.patch`](../patches/pico-imx7/ov5645-v4l2-mode-sync.patch)
  makes `S_FMT` select the sensor mode, prevents the legacy `S_PARM`
  `capturemode` from replacing it, and initializes that mode at stream start.
- [`mx6s-csi-stream-close.patch`](../patches/pico-imx7/mx6s-csi-stream-close.patch)
  stops a still-streaming downstream subdevice before the capture queue is
  released. It uses the source tree's `vb2_is_streaming()` API; a later vendor
  patch uses an unavailable API.

The second patch is required: previously, closing a finite capture could lock
the target. `mx6s_capture.ko` is therefore part of the supported seven-module
replacement set.

## CMA boundary

The running baseline reserves 192 MiB CMA at `0x94000000`. A DTB candidate that
changed the dynamic CMA `size` to 128 MiB was rewritten to 192 MiB before the
kernel consumed it. A second candidate used a static
`reg = <0x94000000 0x08000000>` reservation and booted with 128 MiB CMA.

That 128 MiB candidate completed one 300-frame 1280×720 capture, leaving only
about 7 MiB CMA free, then reset the target during a second 300-frame capture.
The target-side 192 MiB DTB backup was restored; it again passed a 300-frame
1280×720 soak. Keep the 192 MiB CMA reservation. No higher camera resolution
is claimed or required by this workflow.

## Target acceptance

With the corrected modules, a bare command such as:

```bash
v4l2-ctl --device /dev/video1 \
  --set-fmt-video=width=1280,height=720,pixelformat=YUYV \
  --stream-mmap=3 --stream-count=30 --stream-to=/dev/null
```

programs sensor registers `0x3808..0x380b` to `0x0500 × 0x02d0` and completes
normally. Target validation also completed:

- a 30-frame raw YUYV capture (55,296,000 bytes);
- a 300-frame, 10-second 1280×720 YUYV soak at 30 fps, including teardown;
- five clean, byte-identical 30 fps internal colour-bar frames; and
- a five-frame real-scene capture with stable geometry and no wrapping.

The room was dark during the real-scene capture (mean luma 21–23/255), so dark
frames from that session are expected. They still contained stable scene detail
and none of the prior corruption. Captures and contact sheets stay ignored in
`artifacts/device-investigation/`.

The target retains 30-second watchdog and persistent-journal recovery settings
from the investigation. Remove those deliberately if they are no longer wanted.
