# Safe flashing

## Evidence

The source note links TechNexion's Pico i.MX7 and UUU documentation, records
eMMC and USB-boot DIP-switch illustrations, and shows `uuu -lsusb` detecting
an `MX7D` SDP device. [flashing source note](../source-notes/FLASHING.md)

It also records Linux and Windows UUU invocations for a prebuilt Ubuntu image
and Yocto images. Those command lines are historical evidence only. One
self-built-SPL variant is explicitly marked "doesn't work," and the Yocto path
uses an ambiguous wildcard after a `.wic.bz2` path. [flashing source note](../source-notes/FLASHING.md)

## Required safeguards

Flashing is destructive. A Phase 2 tool or runbook must never execute UUU by
default and must require all of the following immediately before execution:

1. An explicit operator confirmation that the intended board is in USB boot
   mode and all other USB download-mode devices are disconnected.
2. A fresh `uuu -lsusb` result shown to the operator; abort unless exactly one
   intended, expected device is selected. Do not select by a remembered bus
   path.
3. Explicit absolute paths to the selected image and boot assets, after file
   existence and non-empty checks. No globs and no inferred decompression
   result.
4. A displayed command, artifact checksum, and a second exact confirmation
   token such as `FLASH` before invoking it.
5. A documented recovery state: return DIP switches to normal eMMC mode only
   after the tool exits and the operator has reviewed its result.

The source notes do not establish partition layout or boot-asset compatibility;
the tool must reject missing compatibility evidence rather than guess.

## Recorded setup lead

The source note records installation prerequisites and a TechNexion-hosted UUU
archive. Obtain and verify the tool/version according to the linked vendor
documentation, then run the discovery safeguard above. [flashing source note](../source-notes/FLASHING.md)
