# Browser and memory policy

The boards have 487 MiB RAM. The maintained setup configures:

- `vm.swappiness=10`;
- a 192 MiB `lzo-rle` zram swap device;
- a solid black Xfce desktop;
- limited Firefox content processes and cache;
- disabled unused Bluetooth/Blueman, ModemManager, udisks/automount, Snap,
  and rsyslog services.

NetworkManager, Wi-Fi, PulseAudio, and WebRTC remain enabled.

## Browsers

Use `netsurf-gtk` for simple internal pages. Firefox remains available for sites
that need features NetSurf lacks.

The Ubuntu 22.04 `chromium-browser` package uses Snap. The supported kernel lacks
SquashFS support, so this Chromium package cannot run on the maintained image.

## Applying the policy

New images include the policy. The [device updater](../BUILD.md#update-existing-boards)
applies the same settings to existing boards.
[`configure-pico-imx7-memory.sh`](../scripts/configure-pico-imx7-memory.sh)
also installs the policy directly; reboot to apply the zram size and desktop
login settings. It does not reset active swap while running.

Firefox defaults live in `/etc/firefox/syspref.js`. They limit processes/cache
and disable saved logins, autofill, spellcheck, new-tab content, telemetry,
prefetching, notifications, and WebGL. WebRTC remains enabled. The preferences
apply when Firefox next starts.
