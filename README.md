# Pico i.MX7 Ubuntu 22.04

Board references: [PICO-PI-IMX7 product page](https://www.technexion.com/products/system-on-modules/evk/pico-pi-imx7/) · [PICO-IMX7 developer documentation](https://developer.technexion.com/docs/system-on-modules/pico/pico-imx7/).

## Flash eMMC over USB

Install the dependencies, build the verified raw image, and fetch the pinned
UUU boot assets:

```bash
sudo apt install --no-install-recommends curl kmod libguestfs-tools unzip xz-utils
./fetch-base-image.sh
./make-image.sh
./fetch-emmc-boot-assets.sh
```

The generated image includes the validated camera stack, a hardware-derived
hostname for each board, and the low-memory policy (including a plain desktop
background) from [`scripts/configure-pico-imx7-memory.sh`](scripts/configure-pico-imx7-memory.sh).
It also includes safe device initialization, Cheese 720p defaults, bounded
journaling, watchdog recovery, and verified group access. See [BUILD.md](BUILD.md)
for exact contents and existing-target configuration.

Inspect both existing boards with the same maintained updater:

```bash
./update-device.sh --target ubuntu@192.168.4.120 \
  --target ubuntu@192.168.1.153 --check
```

Apply a reviewed differential to an explicit target with `--apply`; add
`--camera-test` for bounded 720p capture and stream-close acceptance.

Power the board off before moving the caps. Set the jumpers to Serial Boot Loader mode, connect the USB-C
OTG/power port, and confirm `lsusb -d 15a2:0076` reports the expected device.

```bash
./flash-emmc.sh --flash
```

After UUU completes, restore the normal eMMC boot positions and restart the board.

## PICO-PI-IMX7 boot-jumper positions

These are the four 3-pin jumper caps in the 2×2 boot-control cluster below the
40-pin expansion header, not expansion-header pins. With the expansion header
at the top, use the manual's [Figure 19](https://www.nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf#page=18): its right-hand photo is Serial Boot Loader
(USB download); its left-hand photo is normal eMMC boot.

`**-` bridges the two left pins of a jumper; `-**` bridges the two right pins.

```text
Serial Boot Loader (USB):       Normal eMMC boot:
top row:     -**  **-           top row:     **-  -**
bottom row:  -**  **-           bottom row:  **-  **-
```

### eMMC mode (normal)
![emmc](docs/boot_emmc_normal.jpg)

### Serial Boot Loader / USB boot (flash)
![usb](docs/boot_usb_flash.jpg)

## Development

For rebuilding modules, SD-card images, target access, and camera details, see [BUILD.md](BUILD.md).
