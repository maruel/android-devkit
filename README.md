# Pico i.MX7 Ubuntu 22.04 Wi-Fi and camera modules

This repository builds and packages seven modules for the inspected TechNexion
Pico i.MX7 Ubuntu 22.04 image (kernel `5.15.71`): QCA ath10k Wi-Fi and MIPI
OV5640 camera support. It includes a validated prebuilt set in
[`prebuilt/pico-imx7/ubuntu-22.04-5.15.71`](prebuilt/pico-imx7/ubuntu-22.04-5.15.71),
but you can rebuild it from source.

The base image is intentionally not committed. Obtain the exact raw image with
SHA-256 `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`;
save it as `artifacts/ubuntu-22.04/ubuntu-22.04.raw`. The helpers reject any
other image.

## Create a flash image

```bash
./make-image.sh
```

This uses the tracked prebuilt modules and writes the new image and provenance
record under `artifacts/ubuntu-22.04/`.

## Rebuild the modules

Install the required build tools, clone the pinned TechNexion kernel source,
then run the builder. GCC 12 is required; GCC 14 does not build this tree.

```bash
sudo apt-get install --yes bc dwarves gcc-12-arm-linux-gnueabi libelf-dev lzop libguestfs-tools
./build-drivers.sh
./make-image.sh --rebuilt --output-name pico-imx7-ubuntu-22.04-rebuilt.raw
```

The scripts keep the kernel checkout and build output in `artifacts/`.

## Flash an SD card

First use the dry run and confirm the device independently:

```bash
./flash-sd-card.sh --device /dev/sdX
```

It prints two confirmation strings. Repeat the command with `--flash` and both
exact confirmations to write the whole, unmounted card. Do not use a partition
such as `/dev/sdX1`.

The raw SD image workflow is complete. UUU flashing requires separately
validated SPL, U-Boot, and UUU assets and is intentionally not implied here.

See [the detailed Ubuntu workflow](docs/workflows/ubuntu.md) for provenance,
configuration extraction, and validation details.
