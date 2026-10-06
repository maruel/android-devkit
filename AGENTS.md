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
  when inspecting or replacing `/imx7d-pico-pi.dtb`. During replacement, keep a
  temporary rollback copy on that partition; delete it after verifying the new
  contents. On failure, restore and verify the original, then delete the copy.
  If restoration fails, preserve the only recoverable copy and report its exact
  path as unfinished recovery. Do not retain configuration backups or remove
  unrelated historical backups.
- The inspected camera is the CAM-OV5645 at I²C `3-003c`, using
  `ov5645_camera_mipi_v2.ko`, direct GPIO1_4 power-down, GPIO1_5 reset, and
  CLKO1. The baseline DTB uses a 240 MHz MIPI CSI receiver clock with
  `csis-wclk`; do not change it without new primary evidence. Capture at
  `/dev/video1` is validated at 1280×720 YUYV after the tracked OV5645
  mode-sync and MX6S stream-close patches. Keep `mx6s_capture.ko` in the
  supported prebuilt set for safe stream teardown. Keep the 192 MiB CMA
  reservation and set Cheese photo/video defaults to 1280×720.
  See `docs/camera.md`.
- For an on-device investigation explicitly requested by the user, permission is
  granted to install software, change device state, capture screenshots, and
  reboot the device as needed. Otherwise, ask before running `apt-get install`
  or changing external state.
- The current device names are listed in `README.md`. Use explicit SSH targets;
  use the current IP when renaming or rebooting a board. Their password is
  `ubuntu`; the user has explicitly designated it non-sensitive and it may be
  copied or printed in clear text. After rebooting it, wait at least 40 seconds
  before attempting SSH; use `scripts/reboot-technexion.sh` for an automated
  reboot and readiness check.
- For shell changes, use `shellcheck` and relevant direct command, build, or
  device checks. Keep checks bounded and practical; do not run extended device
  or stress testing unless asked. Diagnose device failures when reported.
  Do not add test files or test harnesses unless the user
  explicitly asks. For code, follow the applicable code-quality skill. Preserve
  unrelated worktree changes.
- Keep documentation focused on current facts, supported settings, and operator
  steps. Keep investigation history in Git history and ignored artifacts.
