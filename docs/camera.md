# CAM-OV5645 camera

The supported capture mode is **1280×720 YUYV at 30 fps** on `/dev/video1`.

## Hardware and drivers

- Sensor: CAM-OV5645 at I²C `3-003c`, using
  `ov5645_camera_mipi_v2.ko`.
- Capture: `mx6s-csi`, using `mx6s_capture.ko`.
- Receiver: `mxc_mipi_csi.ko`, with a 240 MHz clock and `csis-wclk`.
- Power-down: GPIO1_4; reset: GPIO1_5; sensor clock: CLKO1.
- CMA reservation: 192 MiB.

The DTB and module identities are recorded in
[`modules.record`](../prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record).
Keep the receiver settings and CMA reservation unchanged.

## Required patches

The driver build applies these patches to the pinned kernel source:

- [OV5645 mode synchronization](../patches/pico-imx7/ov5645-v4l2-mode-sync.patch)
  makes `S_FMT` select the sensor mode and initializes it at stream start.
- [MX6S stream teardown](../patches/pico-imx7/mx6s-csi-stream-close.patch)
  stops active downstream subdevices before releasing the capture queue and
  guards duplicate `STREAMOFF` calls.
- [MX6S 720p limit](../patches/pico-imx7/mx6s-csi-720p-limit.patch)
  limits capture requests and advertised modes to 1280×720.

## Short capture check

```bash
v4l2-ctl --device /dev/video1 \
  --set-fmt-video=width=1280,height=720,pixelformat=YUYV \
  --stream-mmap=3 --stream-count=30 --stream-to=/dev/null
```

The pinned MX6S driver omits the pixel-format and bytes-per-line fields from
`G_FMT`. Set YUYV explicitly; the 720p frame size is 1,843,200 bytes.

## Cheese

The shared setup policy sets Cheese photo and video resolution to 1280×720.
To set it manually, run these commands in the graphical session:

```bash
gsettings set org.gnome.Cheese photo-x-resolution 1280
gsettings set org.gnome.Cheese photo-y-resolution 720
gsettings set org.gnome.Cheese video-x-resolution 1280
gsettings set org.gnome.Cheese video-y-resolution 720
```

For a working preview, launch Cheese with software rendering:

```bash
LIBGL_ALWAYS_SOFTWARE=1 CLUTTER_BACKEND=x11 COGL_DRIVER=gl \
  cheese --device=/dev/video1
```

Software rendering uses substantial CPU and RAM on this board.

## Browser camera

Firefox can display a camera preview through `getUserMedia()`. Repeated browser
start/stop behavior is not validated by the bounded V4L2 capture check.
