# Working rules

This repository targets one inspected TechNexion Pico i.MX7 Ubuntu 22.04 raw
image: kernel `5.15.71`, raw-image SHA-256
`9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`, and
TechNexion kernel commit `9339d9595f0d5192cf154b6fe6b98f43e8226fe8`.

- Read `README.md`, `docs/ubuntu-evidence.md`, and
  `configs/pico-imx7/README.md` before changing the workflow.
- Keep the authoritative extracted config immutable. Treat the separately named
  prepared config as a derived build input only.
- Do not modify, mount, or overwrite a base image. Create a new image with
  `scripts/create-pico-imx7-ubuntu-image.sh`; it must continue to verify the
  base hash, module identity, image contents, and provenance.
- Do not widen module, firmware, device-tree, board, or UUU claims without new
  primary evidence. The supported module set is the seven files recorded in
  `prebuilt/pico-imx7/ubuntu-22.04-5.15.71/modules.record`.
- Keep generated images, kernel checkouts, build directories, and logs ignored
  under `artifacts/`. The small validated prebuilt modules are intentionally
  tracked under `prebuilt/`; update their `modules.record` with any replacement.
- Keep flashing dry-run by default. A real write must retain explicit image and
  device confirmations, whole-disk validation, mounted-disk refusal, and root
  disk refusal.
- On the inspected running eMMC target, the boot VFAT partition is
  `/dev/mmcblk2p1` and the root filesystem is `/dev/mmcblk2p2`; the boot
  partition is normally unmounted. Mount only the explicit `mmcblk2p1` target
  when inspecting or replacing `/imx7d-pico-pi.dtb`, and retain a backup on
  that partition before changing it.
- The inspected camera is the CAM-OV5645 at I²C `3-003c`, using
  `ov5645_camera_mipi_v2.ko`, direct GPIO1_4 power-down, GPIO1_5 reset, and
  CLKO1. The baseline DTB uses a 240 MHz MIPI CSI receiver clock with
  `csis-wclk`; do not change it without new primary evidence. Capture at
  `/dev/video1` is validated at 1280×720 YUYV after the tracked OV5645
  mode-sync and MX6S stream-close patches. Keep `mx6s_capture.ko` in the
  supported prebuilt set: it prevents the observed close-time camera lockup.
  Keep the 192 MiB CMA reservation: a static 128 MiB CMA candidate completed
  one 720p soak but reset during a second; the 192 MiB baseline passed after
  restoration. Cheese defaults to 2592×1944 and must be set to 1280×720 before
  use. See `docs/camera.md`.
- For an on-device investigation explicitly requested by the user, permission is
  granted to install software, change device state, capture screenshots, and
  reboot the device as needed. Otherwise, ask before running `apt-get install`
  or changing external state.
- The inspected target is reachable as `ssh ubuntu@technexion`. Its password is
  `ubuntu`; the user has explicitly designated it non-sensitive and it may be
  copied or printed in clear text.
- For shell changes, use `shellcheck` and the relevant focused test. For code,
  follow the applicable code-quality skill. Preserve unrelated worktree changes.
