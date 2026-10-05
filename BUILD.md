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
AP6335 Wi-Fi modules. The builder applies all three camera patches (mode
synchronization, safe stream close, and the MX6S 720p size limit) without fuzz
to a Git-free archive of the pinned source, then verifies ARM ABI and literal
vermagic for all seven modules. It does not build or use the older OV5645
camera driver.

The scripts keep the kernel checkout and build output in `artifacts/`.
The wrapper fetches the exact pinned commit and the builder archives it without
changing an existing checkout's HEAD or working files. To select a separately
installed GCC 12 ARM compiler or a fresh output directory, use:

```bash
./build-drivers.sh --cross-gcc /absolute/path/to/arm-linux-gnueabi-gcc-12 \
  --output-dir "$PWD/artifacts/module-build-new"
```

The compiler must target `arm-linux-gnueabi`; other versions and targets are
rejected before creating build output. The build record binds all seven modules
and the DTB to their hashes and records the compiler version/hash, prepared and
build configuration hashes, tracked DTS hash, and all three camera patch hashes.
The derived DTS explicitly reserves 192 MiB CMA and keeps the inherited 240 MHz
CSI receiver clock and `csis-wclk`.

Publication requires two successful updater camera-acceptance runs on the same
board with the same recorded build and boot ID. It refuses legacy records without matching
current DTS and patch attestations, then installs a complete staged set and its
record together:

```bash
./scripts/publish-pico-imx7-modules.sh \
  --module-build "$PWD/artifacts/module-build-new" \
  --acceptance-dir "$PWD/artifacts/target-updates/<first-run>" \
  --acceptance-dir "$PWD/artifacts/target-updates/<second-run>"
```

## Access the inspected target

Connect to the board with:

```bash
SSH_TECHNEXION_TARGET=ubuntu@192.168.1.153 ./scripts/ssh-technexion.sh
```

The helper uses `sshpass`; set `SSH_TECHNEXION_TARGET` explicitly when selecting
`ubuntu@192.168.4.120` (`technexion-126c`) or `ubuntu@192.168.1.153`
(`technexion-1e5d`). Its legacy default is `ubuntu@technexion`.
Select another board with `SSH_TECHNEXION_TARGET=ubuntu@<hostname-or-IP>`;
the reboot helper uses the same variable.
The password is `ubuntu`; it is intentionally non-sensitive and may be used or
recorded in clear text for this inspected development target. Every invocation
is bounded to 120 seconds (including connection setup) and kills a stuck SSH
client after a 10-second grace period. Override the limit for a known long
command with `SSH_TECHNEXION_TIMEOUT_SECONDS=300`. After a reboot, wait at
least 40 seconds before reconnecting; [`scripts/reboot-technexion.sh`](scripts/reboot-technexion.sh)
performs that wait and then checks SSH readiness.

## Update existing boards

Use the explicit-target updater to inspect both boards before applying changes:

```bash
./update-device.sh --target ubuntu@192.168.4.120 \
  --target ubuntu@192.168.1.153 --check
./update-device.sh --target ubuntu@192.168.1.153 --apply --camera-test
```

Inspection is the default. It verifies Ubuntu/kernel/board identity, the boot
kernel, complete hardware UIDs, and short-name collisions across all requested
boards before any writes. It reports the differential against the selected
recorded module/firmware set and shared policy. Applying replaces differing
custom modules; inspect the plan first. Select a rebuilt set with
`--module-build "$PWD/artifacts/module-build-new"`.

The updater verifies installed hashes, dependency metadata, permissions and
groups, reboots only when required, waits at least 40 seconds, and reconnects
by the pinned IP. Configuration backups are not retained. A DTB replacement
uses only `/dev/mmcblk2p1` and a temporary rollback copy, deleted after verified
replacement or verified restoration. Camera acceptance is optional and bounded:
300 frames at 1280×720 YUYV, then an explicit-format reopen and one-frame capture.
Run acceptance twice when validating a replacement build before publication.
Publication requires different updater-generated run IDs and the same verified
boot ID; copying an evidence directory does not establish another acceptance.

`--install-netsurf` offers authenticated package setup and inventories installed
packages and third-party apt sources. Only an unused Vivaldi source is disabled;
other repository failures are reported with bounded apt diagnostics. Apply and
failure evidence stays under `artifacts/target-updates/`.

Images and updates share the same memory, hostname and board policy. The board
policy installs root-owned oneshot initialization, grants group access to
existing audio/video/render devices, and unblocks Wi-Fi without Bluetooth
initialization. Standalone dnsmasq is masked only when systemd-resolved is present
and no custom DNS/DHCP configuration or startup override is found. Persistent
journaling is capped at 32 MiB (8 MiB runtime), with a 30-second hardware
watchdog. Verification checks PID 1 actually owns the watchdog, DNS and SSH
readiness, failed services, hostname, zram, swappiness, 192 MiB CMA, module
identities, and the black background in the actual graphical session. Existing
failed services are reported separately. Cheese photo/video defaults are set
to 1280×720 at graphical login when its schema is available.

## Configure target memory

The target has 487 MiB RAM. For simple web pages, use NetSurf rather than
Firefox: it used roughly 22–26 MiB proportional-set size (PSS) on the inspected
target, versus Firefox's 85–95 MiB. The target has `netsurf-gtk` installed.

Images created by `make-image.sh` already contain this fixed low-memory policy:
`vm.swappiness=10`, a 192 MiB `lzo-rle` zram swap device, Firefox restrictions,
disabled unused services, and a solid black Xfce desktop without wallpaper.
The desktop, panel, and touchscreen applications remain available. The login
helper applies the background to every known monitor and workspace through
`xfconf-query`; it preserves other desktop settings. The image builder verifies each policy file and
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
SSH_TECHNEXION_TARGET=ubuntu@192.168.1.153 \
  ./scripts/ssh-technexion.sh sudo -n bash -s \
  < scripts/configure-pico-imx7-memory.sh
SSH_TECHNEXION_TARGET=ubuntu@192.168.1.153 ./scripts/reboot-technexion.sh
```

The background applies at the next graphical login. To apply it immediately,
run `/usr/local/bin/pico-imx7-plain-background` in the board's graphical
terminal as `ubuntu`. Wallpaper memory savings have not been measured.

## Give each board a unique hostname

New images install a boot-time policy that derives
`technexion-<up to 4 lowercase hex digits>` from the hardware UID in
`/sys/devices/soc0/serial_number`: strip leading zeros, then take the first four
remaining digits (for example, `000001E5D79AC462` becomes `technexion-1e5d`).
It updates `/etc/hostname`, the local hostname mapping in `/etc/hosts`, and the
running hostname before NetworkManager and Avahi start. It runs at every boot,
so one flash image can be used on both inspected boards. It requires a nonzero,
16-digit hexadecimal SoC serial and refuses missing or malformed values.
The inspected boards share the same `/proc/cpuinfo` serial and the last four
digits of their SoC serials; neither is a unique identity. The policy does not
depend on a network interface. These short names distinguish the two inspected
boards; check for collisions when adding more boards.

For an existing target, use its current hostname or IP address:

```bash
SSH_TECHNEXION_TARGET=ubuntu@<current-host-or-IP> \
  ./scripts/ssh-technexion.sh sudo -n bash -s \
  < scripts/configure-pico-imx7-hostname.sh
```

The script prints the new hostname. Reboot using the board's **IP address** for
the readiness check, because its old hostname may stop resolving:

```bash
SSH_TECHNEXION_TARGET=ubuntu@<board-IP> ./scripts/reboot-technexion.sh
SSH_TECHNEXION_TARGET=ubuntu@technexion-1e5d ./scripts/ssh-technexion.sh
```

Use the new hostname or its `.local` name once DHCP/mDNS has updated. Factory
names collide while multiple unconfigured boards are connected; configure them
one at a time or address each by IP.

This repository owns board images, hostnames, drivers, and desktop/memory setup.
`../iot-maruel/technexion/` owns device roles and camera/ESPHome deployment. After
renaming, deploy that appliance using its `DST=ubuntu@<new-hostname>` override;
its Home Assistant discovery identity must also be distinct per board. Hostname
changes require updating existing camera URLs and SSH/deployment destinations.

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
