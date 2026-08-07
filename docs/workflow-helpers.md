# Fail-closed workflow helpers

The scripts in `scripts/` implement the Phase-2 workflow contract. They are
small independent commands: there is intentionally no broad command that
downloads, builds, bundles, and flashes in one invocation.

They do not select a board, image, release, repository, branch, module,
partition, boot asset, USB path, or credential. Until every selected value is
supported by current evidence, the helpers cannot produce a device-specific
image. In particular, this repository does not claim a tested build, boot,
Wi-Fi connection, camera capture, or flash.

## Manifest setup

Create a manifest outside the repository with explicit, reviewed selections.
No prefilled manifest is supplied because a placeholder cannot establish the
board, image, component, boot-asset, or flash-target authority required by the
helpers. The manifest grammar is strict: one known uppercase `KEY=value` pair
per line, no comments, blank lines, duplicate fields, whitespace, shell syntax,
or extra fields. It is parsed as data; it is never sourced.

All selected output locations must be clean absolute paths. Set
`ARTIFACTS_ROOT`, `KERNEL_BUILD_ROOT`, and `CONFIG_OUTPUT_ROOT` to dedicated,
explicit output directories outside this source checkout. Helpers only create
or copy generated artifacts below these roots. URLs containing credentials are
rejected, and no helper records credentials.

`ARTIFACTS_ROOT`, `CONFIG_OUTPUT_ROOT`, every configuration/provenance record,
and every generated output must be disjoint from `KERNEL_CHECKOUT_DIR` in both
directions: none may be the checkout, an ancestor of it, or a descendant of it.
This applies to fetch, configuration extraction, and bundle assembly as well:
they require the planned `KERNEL_CHECKOUT_DIR` in the manifest even when that
checkout will only be created by the later preparation step.

The manifest must also name non-empty evidence files and SHA-256 values for
board identity, Wi-Fi hardware/firmware/component selection, camera
device-tree/test/component selection, and boot-asset compatibility. Build
checks board, Wi-Fi, and camera evidence; bundle checks board and boot evidence.
These files are operator-supplied primary evidence, not facts inferred by these
helpers, and their presence does not claim a tested device result.

The required selected values correspond to the unresolved items in
[workflow status](workflow-status.md): exact base image and checksum, immutable
kernel commit and target release, captured config, Wi-Fi/camera source and
Kconfig choices, compatible boot files, and one i.MX7D SDP USB identity.

## Commands and order

Run these commands individually from the repository root, with the same fully
populated manifest path. They preflight their inputs and stop on the first
missing or mismatched value.

1. Fetch the selected base artifact and verify its mandatory SHA-256. Use
   `BASE_IMAGE_DECOMPRESS=none`, `xz`, or `gzip`; the latter two require a
   separate explicit decompressed destination.

   ```bash
   scripts/fetch-base-image.sh --manifest /absolute/path/phase-2.manifest
   ```

2. Fetch exactly `KERNEL_COMMIT_SHA` into a new detached checkout below
   `KERNEL_BUILD_ROOT`. `KERNEL_COMMIT_SHA` must be a full 40-character SHA;
   the helper fetches that object directly and writes `.workflow-kernel-identity`.

   ```bash
   scripts/prepare-kernel.sh --manifest /absolute/path/phase-2.manifest
   ```

3. Extract the selected configuration. With `CONFIG_SOURCE=archive`, the
   already retrieved `CONFIG_ARCHIVE_PATH` is checked first. With
   `CONFIG_SOURCE=ssh`, explicit host, user, port, remote path, archive output
   path, and mandatory expected archive checksum are required; the helper uses
   `scp`, then validates and decompresses the archive to `CONFIG_DESTINATION`.

   ```bash
   scripts/extract-config.sh --manifest /absolute/path/phase-2.manifest
   ```

4. Configure the detached kernel into the separate `KERNEL_BUILD_DIR`. It
   merges the explicit Wi-Fi and camera Kconfig fragments, runs `olddefconfig`,
   `prepare`, and `modules_prepare`, then verifies every explicit `CONFIG_*=...`
   entry and every `# CONFIG_* is not set` entry remains in the resulting
   `.config`. It refuses an existing build `.config` or configuration record,
   so a new manifest must use a fresh build/output location. It also fails unless
   `make -s kernelrelease` exactly equals `KERNEL_TARGET_RELEASE`. Both
   fragments require selected SHA-256 values; the configuration record binds
   those fragment hashes, board/Wi-Fi/camera evidence hashes, the immutable
   kernel commit, the current source-config checksum, and the final merged
   `.config` checksum. Independent generated paths cannot be equal to, contain,
   or be contained by one another.

   ```bash
   scripts/configure-kernel.sh --manifest /absolute/path/phase-2.manifest
   ```

5. Build the explicitly named Wi-Fi and camera source subdirectories as two
   separate `make M=... modules` invocations. `WIFI_MODULE_KOS` and
   `CAMERA_MODULE_KOS` are ordered, comma-separated non-glob `.ko` filename
   lists (for example, the selected Wi-Fi input may require both `brcmfmac.ko`
   and `brcmutil.ko`). The helper copies every named source-relative output to
   one explicit `MODULE_PUBLICATION_DIR` containing `wifi/`, `camera/`, and
   `modules.record`, published atomically as one directory, and never installs modules. It
   first makes an isolated source staging copy beneath `KERNEL_BUILD_ROOT`, so
   `make M=... modules` cannot write object or module files into the immutable
   selected checkout. It verifies the configuration provenance record before
   building and carries its selected commit, evidence, fragment, source-config,
   and merged-configuration identities into `modules.record`. A failed build removes both
   its temporary publication and its owned source staging directory; a
   successful publication retains the stage for inspection.

   ```bash
   scripts/build-modules.sh --manifest /absolute/path/phase-2.manifest
   ```

6. Assemble a new checksummed image/flash bundle. The helper copies the named
   raw image, SPL, U-Boot, and selected UUU command script into the bundle; it
   does not use globs, mount, or modify the raw base image. `FLASH_EXPECTED_SDP_ID`
   must be written as `imx7d-sdp-VID:PID`, and the bundle includes an invocation
   manifest, including the verified board and boot evidence paths and checksums.
   This is an image/flash bundle, not a successfully boot-tested
   device image.

   ```bash
   scripts/assemble-flash-bundle.sh --manifest /absolute/path/phase-2.manifest
   ```

7. Inspect the bundle with the default dry run. It parses the tabular
   `uuu -lsusb` fields (`Path Chip Pro Vid Pid`), including the protocol value
   `SDP:`, and accepts exactly one explicitly declared i.MX7D SDP VID/PID row.
   Any additional `SDP*:`-family download row, including `SDPS:`, fails closed. The output displays the resolved
   path-restricted `uuu -m PATH SCRIPT` command and every payload
   filename/checksum for operator review, but never invokes UUU to flash in this
   mode.

   ```bash
   scripts/flash-bundle.sh --bundle /absolute/path/to/flash-bundle
   ```

   Flashing additionally requires `--flash` and both exact confirmation values
   printed by the dry run. The first binds consent to the bundle-manifest hash;
   the second binds consent to the declared i.MX7D SDP identity. No `sudo` is
   used and no USB path is inferred. Immediately before the UUU write, the
   helper repeats discovery and requires the same single SDP path; a changed or
   additional SDP target fails closed. The UUU invocation uses that revalidated
   path through `-m`, and its result record reports UUU and log-writer statuses
   separately. After confirmation it copies and rechecks all payloads in a
   private temporary snapshot; UUU is invoked only with the verified snapshot
   script. Run logs use owned per-run directories and reject a symlinked logs
   path.

   ```bash
   scripts/flash-bundle.sh --bundle /absolute/path/to/flash-bundle \
     --flash --confirm-bundle 'FLASH_BUNDLE_SHA256=...' \
     --confirm-device 'FLASH_DEVICE=imx7d-sdp-VID:PID'
   ```

On a real flash, the UUU output is recorded under the bundle's `logs/`
directory. Do not run that command until the physical device, boot assets, and
acceptance evidence have been selected and reviewed.
