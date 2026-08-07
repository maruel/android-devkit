# Phase 2 workflow implementation contract

This is derived documentation for implementation planning. It does not replace
the [raw source notes](../source-notes/) as factual authority.

## Objective and boundary

Implement small, inspectable helpers for obtaining a selected base image,
preparing a selected kernel tree, extracting the image kernel configuration,
building selected Wi-Fi and camera components, assembling a candidate flash
bundle, and guarded flashing. The helpers must not download/build/flash merely
because a broad entry point was invoked.

There must be no universal "do everything" command.

## Inputs that must be explicit

- Board/model identity and evidence source.
- Base-image URL, release identifier, checksum, and destination path.
- Kernel repository URL, immutable commit SHA, target kernel release, and proof
  that the source matches the target module ABI.
- Config source (for example, a captured `/proc/config.gz`), its checksum, and
  extraction destination.
- Wi-Fi hardware identity, module config, firmware/NVRAM source and filenames.
- Camera device-tree/module requirements and acceptance-test parameters.
- Boot assets, image artifact path, checksum, and documented compatibility.
- Flash target-selection expectation and an operator-provided confirmation.

Each must be supplied in a manifest or command arguments; nothing may be
silently selected from a default URL, branch, hardware target, credential,
partition layout, or USB bus path.

## Script boundaries and outputs

| Helper | Inputs | Successful output | Must fail when |
| --- | --- | --- | --- |
| Fetch base image | URL, checksum, destination | verified immutable artifact and checksum record | checksum/source/release missing or mismatched |
| Prepare kernel | repo URL, commit SHA, target release | detached source checkout identity record | ref is mutable, SHA absent, or ABI mapping unproven |
| Extract config | captured config archive, destination | decompressed `.config` plus checksum | archive invalid or target release unknown |
| Build Wi-Fi | kernel tree/config, chosen component spec | modules and build metadata outside source tree | hardware/config/module ABI or firmware naming unresolved |
| Build camera | kernel tree/config, chosen component spec | modules and build metadata outside source tree | device-tree/module/test contract unresolved |
| Assemble flash bundle | approved image and boot assets | manifest with absolute paths and checksums | artifact format or asset compatibility unresolved |
| Flash | approved bundle, fresh discovery output, confirmations | UUU log and exit code | discovery is ambiguous, any file check fails, or confirmations absent |

Outputs must retain input identities, command lines, timestamps, checksums, and
logs so a later phase can audit them. Source trees and downloaded artifacts
must not be modified in place except in explicitly designated work/output
directories.

## Failure behavior and safe defaults

- Every helper is fail-closed, exits nonzero on a missing prerequisite, and
  names the missing evidence.
- Build helpers may compile only after all component requirements above are
  resolved; they must not install modules on a target.
- Assembly may package only explicitly named files and must reject globs.
- The flash helper is separate from every build/download helper, starts in
  dry-run/display mode, and requires two explicit confirmations after a fresh
  UUU discovery result. It must not use `sudo` or alter DIP switches itself.
- No helper may claim a tested build, boot, Wi-Fi connection, camera capture,
  or flash without recorded acceptance evidence.

## Open prerequisites

The implementation cannot proceed to an authoritative end-to-end path until
the blockers in [workflow status](../workflow-status.md) are resolved. The
most important are the exact device/radio identity, selected base image,
kernel ref-to-ABI mapping, Wi-Fi firmware and module settings, camera component
requirements, and compatible flash boot assets.

The available technical leads are retained in the [Yocto](../workflows/yocto.md),
[Ubuntu](../workflows/ubuntu.md), and [flashing](../workflows/flashing.md)
evidence pages.
