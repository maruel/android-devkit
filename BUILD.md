# Build, flash, and validate Pico i.MX7 Ubuntu 22.04

This repository builds and packages seven modules for the inspected TechNexion
Pico i.MX7 Ubuntu 22.04 image (kernel `5.15.71`): AP6335 BCM4339 Broadcom
FullMAC SDIO Wi-Fi and the vendor CAM-OV5645 MIPI-camera stack. It includes a prebuilt set in
[`prebuilt/pico-imx7/ubuntu-22.04-5.15.71`](prebuilt/pico-imx7/ubuntu-22.04-5.15.71),
but you can rebuild it from source.

## Create a flash image

The base image is intentionally not committed. Obtain the exact raw image with
SHA-256 `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`.

```bash
sudo apt install --no-install-recommends curl xz-utils
sudo apt install --no-install-recommends kmod libguestfs-tools
./fetch-base-image.sh
./make-image.sh
```

This fetches pinned AP6335 firmware and NVRAM, uses the tracked prebuilt
modules, and writes `pico-imx7-ubuntu-22.04-brcm.raw` plus provenance under
`artifacts/ubuntu-22.04/`.
It tries `guestfish` without privilege first. If the host kernel is unreadable
to its helper VM, it requests your `sudo` password, retries with elevation, and
hands ownership of its temporary archives back to you. The script does not
modify `/boot`; the downloaded base image and new output remain handled as your
normal user.

## Rebuild the modules

Install the kernel build tools, then run the builder. GCC 12 is required; GCC
14 does not build this tree.

```bash
sudo apt install --no-install-recommends \
  bc bison build-essential dwarves flex gcc-12-arm-linux-gnueabi \
  git libelf-dev libssl-dev patch
./build-drivers.sh
```

This builds the vendor V2 OV5645 driver,
`ov5645_camera_mipi_v2.ko`, with the tracked mode-synchronization patch, and
`mx6s_capture.ko` with the stream-close patch that prevents the observed
close-time lockup. It also rebuilds the required MIPI CSI, legacy capture, and
AP6335 Wi-Fi modules. The builder applies both camera patches exactly to a
Git-free archive of the pinned source, then verifies ARM ABI and literal
vermagic for all seven modules. It does not build or use the older OV5645
camera driver.

The scripts keep the kernel checkout and build output in `artifacts/`.

## Access the inspected target

Connect to the board with:

```bash
./scripts/ssh-technexion.sh
```

The helper uses `sshpass` to connect noninteractively to `ubuntu@technexion`.
The password is `ubuntu`; it is intentionally non-sensitive and may be used or
recorded in clear text for this inspected development target. Every invocation
is bounded to 120 seconds (including connection setup) and kills a stuck SSH
client after a 10-second grace period. Override the limit for a known long
command with `SSH_TECHNEXION_TIMEOUT_SECONDS=300`.

## Configure target memory

The target has 487 MiB RAM. For simple web pages, use NetSurf rather than
Firefox: it used roughly 22–26 MiB proportional-set size (PSS) on the inspected
target, versus Firefox's 85–95 MiB. The target has `netsurf-gtk` installed.

Images created by `make-image.sh` already contain this fixed low-memory policy:
`vm.swappiness=10`, a 192 MiB `lzo-rle` zram swap device, Firefox restrictions,
and disabled unused services. The image builder verifies each policy file and
records its hashes in image provenance.

[`scripts/configure-pico-imx7-memory.sh`](scripts/configure-pico-imx7-memory.sh)
repairs an existing flashed target with the same policy: `vm.swappiness=10`
immediately, and a 192 MiB `lzo-rle` zram swap device at the next boot. It also writes Firefox
system preferences that reduce content processes/cache and disable saved
logins, form fill, spellcheck, telemetry, new-tab services, notifications,
and WebGL. WebRTC remains enabled for camera use. It also disables unused
Bluetooth and Blueman, ModemManager, udisks/automount, Snap services, and
rsyslog. It deliberately does not reset active swap, so reboot after configuring
the board. The inspected
Ubuntu target permits this noninteractive `sudo` invocation:

```bash
./scripts/ssh-technexion.sh sudo -n bash -s \
  < scripts/configure-pico-imx7-memory.sh
./scripts/ssh-technexion.sh sudo -n reboot
```

## Verify the camera on the target

The validated camera is `/dev/video1`. A bare `v4l2-ctl --set-fmt-video`
request now configures the selected sensor mode and supports bounded 1280×720
YUYV capture; the corrected prebuilt set includes `mx6s_capture.ko` for safe
stream teardown. See [camera validation](docs/camera.md) for
target evidence and [hardware acceleration](docs/acceleration.md)
for the separate PxP/codec inventory.

## Build an image from rebuilt modules

Image creation also requires `guestfish` and `depmod`, supplied by
`libguestfs-tools` and `kmod` respectively. Install them first if you did not
already run the prebuilt-image command above:

```bash
sudo apt install --no-install-recommends kmod libguestfs-tools
./make-image.sh --rebuilt --output-name pico-imx7-ubuntu-22.04-rebuilt.raw
```

`--rebuilt` is required here: without it, `make-image.sh` deliberately uses the
tracked, already-validated prebuilt modules. Both paths install the corrected
`ov5645_camera_mipi_v2.ko` and `mx6s_capture.ko` into the new image.

## Flash an SD card

First use the dry run and confirm the device independently:

```bash
./flash-sd-card.sh --device /dev/sdX
```

It prints two confirmation strings. Repeat the command with `--flash` and both
exact confirmations to write the whole, unmounted card. Do not use a partition
such as `/dev/sdX1`.

## Flash eMMC over USB

Fetch the pinned TechNexion UUU package and its matching Pico i.MX7 boot
assets, then set the board DIP switches to USB boot and connect its USB OTG
port. The script confirms the expected NXP USB identity (`MX7D SDP`,
`15a2:0076`) and is dry-run by default:

```bash
sudo apt install --no-install-recommends curl unzip
./fetch-emmc-boot-assets.sh
./flash-emmc.sh
```

See [Ubuntu build evidence](docs/ubuntu-evidence.md) for provenance,
configuration extraction, and validation details.
