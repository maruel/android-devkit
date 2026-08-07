# Working rules

This repository targets one inspected TechNexion Pico i.MX7 Ubuntu 22.04 raw
image: kernel `5.15.71`, raw-image SHA-256
`9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed`, and
TechNexion kernel commit `9339d9595f0d5192cf154b6fe6b98f43e8226fe8`.

- Read `README.md`, `docs/workflows/ubuntu.md`, and
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
- Ask the user before running `apt-get install` or changing external state.
- For shell changes, use `shellcheck` and the relevant focused test. For code,
  follow the applicable code-quality skill. Preserve unrelated worktree changes.
