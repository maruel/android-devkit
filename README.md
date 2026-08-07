# Pico i.MX7 Ubuntu 22.04 Wi-Fi and camera modules

This repository builds and packages seven modules for the inspected TechNexion
Pico i.MX7 Ubuntu 22.04 image (kernel `5.15.71`): QCA ath10k Wi-Fi and MIPI
OV5640 camera support. It includes a validated prebuilt set in
[`prebuilt/pico-imx7/ubuntu-22.04-5.15.71`](prebuilt/pico-imx7/ubuntu-22.04-5.15.71),
but you can rebuild it from source.

The base image is intentionally not committed. Obtain the exact raw image with
SHA-256 `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`;
download and verify it with:

```bash
./fetch-base-image.sh
```

## Create a flash image

```bash
sudo apt install --no-install-recommends curl xz-utils
sudo apt install --no-install-recommends kmod libguestfs-tools
./fetch-base-image.sh
./make-image.sh
```

This uses the tracked prebuilt modules and writes the new image and provenance
record under `artifacts/ubuntu-22.04/`. It prompts for your `sudo` password
for `guestfish`, plus a controlled ownership handoff of its temporary archive.
`guestfish` needs to read the host kernel while starting its private helper VM.
The script does not modify `/boot`; the downloaded base image and new output
remain handled as your normal user.

## Rebuild the modules

Install the kernel build tools, then run the builder. GCC 12 is required; GCC
14 does not build this tree.

```bash
sudo apt install --no-install-recommends bc dwarves gcc-12-arm-linux-gnueabi libelf-dev
./build-drivers.sh
```

The scripts keep the kernel checkout and build output in `artifacts/`.

## Build an image from rebuilt modules

Image creation also requires `guestfish` and `depmod`, supplied by
`libguestfs-tools` and `kmod` respectively. Install them first if you did not
already run the prebuilt-image command above:

```bash
sudo apt install --no-install-recommends kmod libguestfs-tools
./make-image.sh --rebuilt --output-name pico-imx7-ubuntu-22.04-rebuilt.raw
```

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

### PICO-PI-IMX7 boot-jumper positions

These are **four 3-pin jumper caps**, not the expansion-header pins or other
switches. Use [Figure 19 of the PICO-PI-IMX7 hardware manual](https://www.nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf#page=18)
as the physical reference: with the 40-pin expansion header along the top of
the photo, the 2×2 boot-control cluster is directly **below** it and to the
right of the AP6335 Wi-Fi module. The manual's **right-hand** photo is the
required Serial Boot Loader (USB download) configuration; its **left-hand**
photo is normal eMMC boot. Match the four caps to the photograph exactly.

Direct links: [boot-control photograph (Figure 19, page 18)](https://www.nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf#page=18) · [full PICO-PI-IMX7 hardware manual](https://www.nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf).

`**-` bridges the two pins on the left of one three-pin jumper; `-**` bridges the two on the right.

```text
Serial Boot Loader (USB):       Normal eMMC boot:
top row:     -**  **-           top row:     **-  -**
bottom row:  -**  **-           bottom row:  **-  **-
```

eMMC mode (normal)
![emmc](docs/boot_emmc_normal.png)

USB boot (flash)
[!usb](docs/boot_usb_flash.png)

Power the board off before moving the caps. Use the USB-C OTG/power connector
for the host data cable; the micro-USB connector is the serial-console
interface. Before flashing, `lsusb -d 15a2:0076` must show one device.

To erase and write eMMC, run `./flash-emmc.sh --flash` and approve its `[Y/n]`
prompt. The fetched files live under the ignored `artifacts/uuu-assets/pico-imx7/`;
you can override them with
`--spl`, `--u-boot`, and `--uuu` only when you have separately validated
compatibility. After UUU completes, return the DIP switches to normal eMMC
boot before restarting.

See [the detailed Ubuntu workflow](docs/workflows/ubuntu.md) for provenance,
configuration extraction, and validation details.
