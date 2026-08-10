# Pico i.MX7 documentation

The supported target is one inspected TechNexion PICO-PI-IMX7 running Ubuntu
22.04 with kernel `5.15.71`. This directory records the facts and validation
results behind the reproducible build workflow.

## Start here

- [Flash an eMMC image](../README.md) — the end-to-end operator flow, including
  USB-boot jumper positions.
- [Build and validate](../BUILD.md) — rebuild drivers, create an image, access
  the target, and run the camera check.
- [Platform](platform.md) — supported hardware, module set, and non-negotiable
  workflow constraints.

## Detailed records

- [Ubuntu build evidence](reference/ubuntu-evidence.md) — image, kernel,
  configuration, module, firmware, and image-creation identities.
- [Camera validation](validation/camera.md) — corruption cause, corrected
  drivers, target tests, and limits.
- [Hardware-acceleration inventory](validation/acceleration.md) — verified
  display/GPU devices and codec limitations.

Git history retains superseded research and earlier workflow notes; this
location contains only the current supported Ubuntu workflow.
