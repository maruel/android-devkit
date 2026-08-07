# Yocto workflow evidence

This is a sourced research path, not an approved build recipe. Resolve the
[workflow blockers](../workflow-status.md) before running it.

## Recorded manifest candidates

The notes record these TechNexion manifest combinations:

| Candidate | Recorded manifest and setup | Status in notes |
| --- | --- | --- |
| Mickledore | branch `mickledore_6.1.y-stable`, manifest `imx-6.1.55-2.2.0.xml`, `MACHINE=pico-imx7`, `BASEBOARD=pi` | Recorded as the main attempt. |
| Scarthgap | branch `scarthgap_6.6.y-stable`, manifest `imx-6.6.52-2.2.0.xml` | Recorded as not working. |
| Sumo | branch `sumo_4.14.y_GA-stable`, manifest `imx-4.14.98-2.3.5.xml` | Docker environment is recorded as too old. |

Source: [Yocto source note](../source-notes/YOCTO.md), including its links to
the TechNexion manifest and build documentation.

## Source-derived build outline

After the release is explicitly selected, the source note records this outline:

1. Initialize and synchronize the selected TechNexion manifest with `repo`.
2. Source `tn-setup-release.sh -b build` with the selected machine/baseboard
   environment.
3. Build either `core-image-base` or `imx-image-multimedia`; the notes say
   `imx-image-full` is unsupported on i.MX7D.
4. Inspect `build/tmp/deploy/images/pico-imx7/` and record the exact artifact
   chosen for flashing.

These steps and image names are reported in the [Yocto source note](../source-notes/YOCTO.md);
they have not been rerun here.

## Wi-Fi customization: unresolved

The note proposes a custom layer and a kernel config fragment containing
`CONFIG_BRCMFMAC=m` plus BCDC, USB, PCIe, and SDIO settings. It also lists
potential image packages and autoload values. None is accepted as a working
configuration because the same note says the proposed `WIFI_MODULE=brcm`
setting had no effect, and labels several package names as unverified.
[Yocto source note](../source-notes/YOCTO.md)

Phase 2 must inspect the selected release's recipes, image manifest, device
tree, kernel config, module ABI, and firmware search names before changing a
layer. It must then verify the built root filesystem contains the selected
module and firmware rather than assuming package names.

## Flash artifact handoff

The source note records `.wic.bz2` and `.sdcard.bz2` output names, while the
flashing note includes a decompression command and a UUU command with an
ambiguous wildcard path. Do not derive a flash command from that wildcard.
Record the exact, decompressed artifact path and its checksum as a Phase 2
output before any flash action. [Yocto source note](../source-notes/YOCTO.md)
[flashing source note](../source-notes/FLASHING.md)
