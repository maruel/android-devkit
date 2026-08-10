# Supported Pico i.MX7 platform

This repository supports one inspected TechNexion PICO-PI-IMX7 Ubuntu 22.04
image, not a general TechNexion or i.MX7 distribution:

- raw-image SHA-256:
  `9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`;
- kernel release `5.15.71` and TechNexion source commit
  `9339d9595f0d5192cf154b6fe6b98f43e8226fe8`;
- normal target root and boot partitions: `/dev/mmcblk2p2` and
  `/dev/mmcblk2p1` respectively;
- target Wi-Fi: AP6335/Broadcom BCM4339 (`0x02d0:0x4335`), using the tracked
  BRCM device tree and firmware;
- target camera: CAM-OV5645 at I²C `3-003c`, captured through `/dev/video1`.

The [configuration provenance](../configs/pico-imx7/README.md) distinguishes
between the immutable image extraction and the derived build input. Do not
modify the extracted configuration.

## Supported replacement set

The image workflow accepts exactly the seven modules listed in
[`prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record`](../prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record).
This includes `mx6s_capture.ko`, which is required for safe camera stream
teardown. The builder and image creator verify the target ABI, module identity,
firmware, device tree, image contents, and provenance before publishing an
output.

## Safety boundaries

- Never modify, mount, or overwrite the downloaded base image; create a new
  image with `scripts/create-pico-imx7-ubuntu-image.sh`.
- Flashing is dry-run by default. A real write requires the wrapper's explicit
  image and device confirmations.
- Do not alter the target boot partition except when deliberately replacing its
  `imx7d-pico-pi.dtb`; mount only `/dev/mmcblk2p1` and retain a target-side
  backup first.
- Keep the inherited 240 MHz MIPI CSI receiver clock and `csis-wclk`. The
  tested camera configuration is documented in
  [camera validation](validation/camera.md).
