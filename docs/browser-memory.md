# Browser memory observations

The inspected target has 487 MiB RAM and a 122 MiB `lzo-rle` zram swap device
by default. Firefox and NetSurf measurements used `https://example.com` with no
existing browser session. Chromium was requested for `https://perdu.com`, but
could not start because the required Snap cannot mount on this kernel.

## Measured browsers

| Browser | Result | Memory on a simple page |
| --- | --- | --- |
| Firefox 125 | Opened successfully | about 85–95 MiB PSS; 104–112 MiB RSS |
| NetSurf GTK | Opened successfully | about 22–26 MiB PSS; about 36 MiB RSS |

NetSurf displayed the page as `Example Domain - NetSurf` in the target X11
session. `netsurf-gtk` is installed on the inspected target. It is the
recommended browser for simple internal pages; Firefox remains available for
sites that require features NetSurf lacks.

## Swap policy

The default `vm.swappiness=60` caused zram to become nearly full during Firefox
experiments. With a freshly reset zram device and temporary `vm.swappiness=10`,
the same one-page Firefox test used 14.3 MiB zram while running. Lowering
swappiness is the useful control; Firefox low-memory preferences (one renderer,
disabled Fission, and an 8 MiB memory cache) did not materially lower its
single-page PSS.

[`scripts/configure-pico-imx7-memory.sh`](../scripts/configure-pico-imx7-memory.sh)
installs the selected persistent policy: `vm.swappiness=10` and a 192 MiB
`lzo-rle` zram device after reboot. It does not reset active swap while running.

## Firefox feature profile

The same script writes the system default preferences in `/etc/firefox/syspref.js`.
They limit content processes/cache and turn off saved logins, login autofill,
form fill, spellcheck, new-tab content, Pocket, telemetry, Normandy studies,
prefetching, notifications, and WebGL. WebRTC remains enabled for camera use.
The profile also permits low-memory tab unloading.

These settings are deliberately feature-restrictive for the target's vetted
internal sites. They apply when Firefox next starts, but do not eliminate its
roughly 85 MiB single-page baseline.

The script also masks Bluetooth/Blueman, ModemManager, udisks/automount, and
Snap units, disables rsyslog, and prevents the Blueman desktop applet from
starting. After the change and reboot, available RAM rose from
about 210 MiB to about 278 MiB in comparable idle observations. NetworkManager,
Wi-Fi, PulseAudio, and WebRTC remain enabled.

## Chromium is currently unavailable

On this Ubuntu 22.04 image, `chromium-browser` is only a transition package for
the Chromium Snap; no native Chromium package is available. A Chromium Snap
install was attempted but did not install:

```text
system does not fully support snapd: cannot mount squashfs image using squashfs:
unknown filesystem type 'squashfs'
```

The target has no SquashFS filesystem or module, and no FUSE device/module, so
installing `squashfuse` is not a fallback. Chromium cannot be measured until
kernel SquashFS support is added. That is a separate kernel-change task and is
not justified solely for simple-page browsing.

The target's intended use is vetted internal sites, so `--no-sandbox` is
acceptable under that stated threat model if Chromium later becomes available.
It does not solve Snap's mounting requirement and would not eliminate
Chromium's browser, GPU, network, or utility processes; it is not expected to
make Chromium competitive with NetSurf on this RAM budget.
