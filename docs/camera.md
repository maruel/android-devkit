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
- [OV5645 bounded night exposure](../patches/pico-imx7/ov5645-bounded-night-exposure.patch)
  permits automatic exposure extension with an explicit, read-only module option.
- [MX6S stream teardown](../patches/pico-imx7/mx6s-csi-stream-close.patch)
  stops active downstream subdevices before releasing the capture queue and
  guards duplicate `STREAMOFF` calls.
- [MX6S 720p limit](../patches/pico-imx7/mx6s-csi-720p-limit.patch)
  limits capture requests and advertised modes to 1280×720.

## Low-light surveillance

The tracked prebuilt OV5645 module does not yet expose the night option. Run
`./build-drivers.sh` and install the rebuilt sensor module before opting in.
The companion `mx6s_capture.ko` must carry the complete required stream teardown
patch; install the rebuilt companion if the existing module predates it.
The rebuilt driver defaults to the vendor exposure policy. Its read-only
`night_max_exposure_ms` module parameter accepts 0 through 130; zero disables
extension. To opt in on the 640×480 surveillance cameras, add this line to
`/etc/modprobe.d/ov5645-night.conf` before loading the rebuilt module:

```text
options ov5645_camera_mipi_v2 night_max_exposure_ms=130
```

Stop the camera service before unloading/reloading the camera stack, or reboot
with the setting installed. Inspect the loaded option with:

```bash
cat /sys/module/ov5645_camera_mipi_v2/parameters/night_max_exposure_ms
```

Keep the opt-in configuration paired with a rebuilt module that exposes
`night_max_exposure_ms`. The updater refuses both inspection and installation
when its selected OV5645 module lacks the option but
`/etc/modprobe.d/ov5645-night.conf` enables it. Select a compatible rebuilt set
with `--module-build`, or remove the opt-in before restoring tracked prebuilt
modules. Removing the file disables the option on the next module load.

The driver recalculates the ceiling from the active sensor clock and horizontal
line length after each mode initialization. Both frequency-specific ceilings
are limited to 4095 lines because the documented 50 Hz ceiling is 12 bits; the
upper debug bits are preserved. At the supported VGA timing (24 MHz input,
56 MHz timing clock, 1896 clocks per line), 130 ms gives a 3839-line ceiling.
The existing automatic exposure, automatic gain and 15.5× gain ceiling remain.

The surveillance agent outputs 5 Hz, but the sensor still runs at about 30 Hz
in bright light: the vendor VGA driver does not support the requested 5 Hz
mode, and the agent continues with 30 Hz timing.
Night exposure reduces the sensor frame rate only when the illumination requires
longer integration, reaching roughly 7–8 Hz at the VGA ceiling. It also increases motion blur. This option changes the
capture timing contract: validate fresh encoded 5 Hz delivery, bright-light
recovery and stream reopen before enabling it for a surveillance service. Leave
it at zero for applications requiring the original fixed sensor rate. The
module's setting applies to every OV5645 instance using it, and other resolutions
may reach the 4095-line cap before the requested millisecond ceiling.

The register contract comes from the [OmniVision OV5645 specification,
revision 2.01](https://www.pdapply.com/upload/OV5645_CSP3_DS_2.01_.pdf), sections
4.6.1.3 and 7.7. In particular, writing an 180 ms VGA ceiling to the 50 Hz
register would overwrite debug bits.

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
