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

The raw SD image workflow is complete. UUU flashing requires separately
validated SPL, U-Boot, and UUU assets and is intentionally not implied here.

See [the detailed Ubuntu workflow](docs/workflows/ubuntu.md) for provenance,
configuration extraction, and validation details.
