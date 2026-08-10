# Pico i.MX7 documentation

The supported target is one inspected TechNexion PICO-PI-IMX7 running Ubuntu
22.04 with kernel `5.15.71`. This directory records the facts and validation
results behind the reproducible build workflow.

## Current records

- [Platform](platform.md) — supported hardware and module set.
- [Ubuntu build evidence](ubuntu-evidence.md) — image, kernel,
  configuration, module, firmware, and image-creation identities.
- [Camera validation](camera.md) — corruption cause, corrected
  drivers, target tests, and limits.
- [Hardware-acceleration inventory](acceleration.md) — verified
  display/GPU devices and codec limitations.
- [Browser memory observations](browser-memory.md) — measured browser memory,
  swap policy, and the current Chromium limitation.

Git history retains superseded research and earlier workflow notes; this
location contains only the current supported Ubuntu workflow.
