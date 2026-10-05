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

The receiver baseline uses a 240 MHz MIPI CSI clock with `csis-wclk`. The
current derived boot DTB identity is recorded in
[`modules.record`](../prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record).
Three temporary variants
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

Three patches are replayed on a Git-free archive of the pinned kernel source for
each driver build:

- [`ov5645-v4l2-mode-sync.patch`](../patches/pico-imx7/ov5645-v4l2-mode-sync.patch)
  makes `S_FMT` select the sensor mode, prevents the legacy `S_PARM`
  `capturemode` from replacing it, and initializes that mode at stream start.
- [`mx6s-csi-stream-close.patch`](../patches/pico-imx7/mx6s-csi-stream-close.patch)
  stops a still-streaming downstream subdevice before the capture queue is
  released. It uses the source tree's `vb2_is_streaming()` API; a later vendor
  patch uses an unavailable API. It also snapshots whether the capture queue
  was streaming before `vb2_streamoff()` and stops the downstream receiver only
  for a successful active-to-stopped transition. Duplicate STREAMOFF still
  cancels queued buffers but does not stop the receiver again.
- [`mx6s-csi-720p-limit.patch`](../patches/pico-imx7/mx6s-csi-720p-limit.patch)
  restricts capture requests and advertised frame sizes/intervals to at most
  1280×720.

The second patch is required: previously, closing a finite capture could lock
the target. `mx6s_capture.ko` is therefore part of the supported seven-module
replacement set. The pinned receiver drops a runtime-PM reference on every
`s_stream(false)` call, while `vb2_streamoff()` also succeeds for an already
stopped queue. A captured ioctl trace showed v4l2-ctl issuing STREAMOFF twice;
the repeated call never returned and the board subsequently restarted. The
capture driver's transition guard prevents duplicate receiver register access
and runtime-PM reference drops; the trace identifies the blocking ioctl rather
than the precise instruction inside the receiver.

## CMA boundary

The running baseline reserves 192 MiB CMA at `0x94000000`. A DTB candidate that
changed the dynamic CMA `size` to 128 MiB was rewritten to 192 MiB before the
kernel consumed it. A second candidate used a static
`reg = <0x94000000 0x08000000>` reservation and booted with 128 MiB CMA.

That 128 MiB candidate completed one 300-frame 1280×720 capture, leaving only
about 7 MiB CMA free, then reset the target during a second 300-frame capture.
The target-side 192 MiB DTB backup was restored; it again passed a 300-frame
1280×720 soak. The derived DTS now explicitly declares that 192 MiB size instead of relying
on the bootloader to rewrite the vendor reservation. Keep the 192 MiB CMA
reservation. No higher camera resolution
is claimed or required by this workflow.

## Target acceptance

The source-attested prebuilt set passed two separate untraced updater
acceptances on `technexion-1e5d` during the same boot: each captured 300 frames
at 1280×720 YUYV and reopened for an explicit-format one-frame capture. The
repeat updater applied no changes and requested no reboot. Both verified the
same boot ID, watchdog ownership, memory policy, module identities, and actual
Xfce background. This is bounded acceptance for the inspected camera and mode;
browser start/stop behavior remains outside that check.

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

## Browser Web API

A local `getUserMedia()` page in Firefox 125 requested an ideal 640×480 camera
stream. The camera image was visibly displayed on the target during this
investigation, so the Web API can produce a working preview. My automated
frame-change check was not a valid basis for rejecting that result: Firefox 125
lacks `HTMLVideoElement.requestVideoFrameCallback()`, and the fallback polling
check did not reliably distinguish a live display from its own page/runtime
failure.

Firefox probes unsupported RGB V4L2 formats before selecting YUYV. Two
temporary MX6S candidates that converted those probes to YUYV (and one that
also hid modes above 1280×720) were not stable across repeated automated
Firefox starts. They were removed and the validated `mx6s_capture.ko` restored;
it again passed a 300-frame 1280×720 soak. Thus the observed Firefox preview is
encouraging, but repeatable browser start/stop behaviour has not yet been
validated. It should not be described as unsupported.

## Cheese preview

Cheese 41 initially selected its saved default 2592×1944 photo and video
resolution. It displayed one frame and then stopped updating; the target later
reset under that unvalidated high-resolution capture. There were no MIPI CSI
errors before the reset. The application must be restricted to the validated
mode:

```bash
gsettings set org.gnome.Cheese photo-x-resolution 1280
gsettings set org.gnome.Cheese photo-y-resolution 720
gsettings set org.gnome.Cheese video-x-resolution 1280
gsettings set org.gnome.Cheese video-y-resolution 720
```

After restarting Cheese, `/dev/video1` reported 1280×720 (1,843,200-byte
frames), but its normal Clutter/Cogl preview still froze: two captures of the
actual 620×480 preview window five seconds apart had zero changed pixels. A
direct GStreamer source soak passed 300 1280×720 frames, so the capture path is
not the cause.

The working workaround forces Cogl through software rendering:

```bash
LIBGL_ALWAYS_SOFTWARE=1 CLUTTER_BACKEND=x11 COGL_DRIVER=gl \
  cheese --device=/dev/video1
```

With that environment, the preview changed in all six five-second intervals of
a 30-second sample. The likely bug is in the Vivante GPU driver's interaction
with Cheese's Clutter/Cogl preview renderer, not in the camera driver: the
camera produced 300 frames through GStreamer while the hardware-rendered preview
was frozen. Software rendering costs about 125 MiB RSS and roughly one and a
half CPU cores; do not run a heavy browser alongside it without observing
available RAM and zram.

The shared setup policy retains a 30-second watchdog and bounded persistent
journaling. Verification requires an open watchdog descriptor owned by PID 1.
