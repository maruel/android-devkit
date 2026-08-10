#!/usr/bin/env bash
set -euo pipefail

readonly zram_size_mib=192
readonly swappiness=10
readonly zram_algorithm='lzo-rle'
readonly sysctl_config='/etc/sysctl.d/90-pico-imx7-memory.conf'
readonly zram_initializer='/usr/local/sbin/pico-imx7-zram-init'
readonly zram_drop_in='/etc/systemd/system/zram-config.service.d/10-pico-imx7-memory.conf'
readonly firefox_preferences='/etc/firefox/syspref.js'
readonly blueman_autostart='/home/ubuntu/.config/autostart/blueman.desktop'
readonly -a masked_services=(
  bluetooth.service
  blueman-mechanism.service
  ModemManager.service
  udisks2.service
  rsyslog.service
  snapd.service
  snapd.socket
  snapd.seeded.service
  snapd.autoimport.service
  snapd.apparmor.service
)

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' "usage: $(basename -- "$0") [--image-root /absolute/path]" >&2
  exit 2
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

require_directory() {
  [[ -d "$1" && ! -L "$1" ]] || fail "required directory is missing or symlinked: $1"
}

require_regular_or_missing_file() {
  [[ ! -e "$1" || ( -f "$1" && ! -L "$1" ) ]] ||
    fail "destination must be a regular file or absent: $1"
}

root_path() {
  local path="$1"
  [[ "$path" == /* ]] || fail "policy path must be absolute: $path"
  if [[ -n "$image_root" ]]; then
    printf '%s%s\n' "$image_root" "$path"
  else
    printf '%s\n' "$path"
  fi
}

install_mask() {
  local destination="$1"
  if [[ -e "$destination" && ! -L "$destination" ]]; then
    fail "mask destination is not a symlink or absent: $destination"
  fi
  ln -sfn -- /dev/null "$destination"
}

image_root=''
if (($# == 0)); then
  mode='target'
elif [[ $# == 2 && $1 == --image-root ]]; then
  mode='image'
  image_root="$2"
  [[ "$image_root" == /* ]] || fail '--image-root must be absolute'
  require_directory "$image_root"
else
  usage
fi
readonly mode image_root

for command in cat chown dirname install ln mkdir mktemp rm tr; do
  require_command "$command"
done
if [[ "$mode" == target ]]; then
  for command in modprobe mkswap swapon sysctl systemctl; do
    require_command "$command"
  done
fi

if [[ "$mode" == target ]]; then
  [[ "$(id -u)" == 0 ]] || fail 'run this script as root'
  require_command awk
  memory_kib="$(awk '$1 == "MemTotal:" { print $2; exit }' /proc/meminfo)"
  [[ "$memory_kib" =~ ^[0-9]+$ ]] || fail 'could not determine installed memory'
  ((memory_kib >= zram_size_mib * 1024)) ||
    fail "${zram_size_mib} MiB zram exceeds installed memory"
  [[ -r /sys/block/zram0/comp_algorithm ]] || fail 'zram0 compression settings are not available'
  available_algorithms="$(tr -d '[]' < /sys/block/zram0/comp_algorithm)"
  case " $available_algorithms " in
    *" $zram_algorithm "*) ;;
    *) fail "zram algorithm is unavailable: $zram_algorithm (available:$available_algorithms)" ;;
  esac
fi

sysctl_destination="$(root_path "$sysctl_config")"
zram_initializer_destination="$(root_path "$zram_initializer")"
zram_drop_in_destination="$(root_path "$zram_drop_in")"
firefox_preferences_destination="$(root_path "$firefox_preferences")"
blueman_autostart_destination="$(root_path "$blueman_autostart")"
readonly sysctl_destination zram_initializer_destination zram_drop_in_destination
readonly firefox_preferences_destination blueman_autostart_destination

for directory in \
  "$(dirname -- "$sysctl_destination")" \
  "$(dirname -- "$zram_initializer_destination")" \
  "$(dirname -- "$zram_drop_in_destination")" \
  "$(dirname -- "$firefox_preferences_destination")" \
  "$(dirname -- "$blueman_autostart_destination")"; do
  mkdir -p -- "$directory"
  require_directory "$directory"
done
for destination in "$sysctl_destination" "$zram_initializer_destination" \
  "$zram_drop_in_destination" "$firefox_preferences_destination" \
  "$blueman_autostart_destination"; do
  require_regular_or_missing_file "$destination"
done

for service in "${masked_services[@]}"; do
  mask_destination="$(root_path "/etc/systemd/system/$service")"
  install_mask "$mask_destination"
done

work_parent='/tmp'
if [[ "$mode" == image ]]; then
  work_parent="$image_root"
fi
work_dir="$(mktemp -d "$work_parent/.pico-imx7-memory.XXXXXX")"
readonly work_dir
cleanup() {
  rm -rf -- "$work_dir"
}
trap cleanup EXIT HUP INT TERM

cat > "$work_dir/sysctl.conf" <<EOF
# Managed by configure-pico-imx7-memory.sh.
vm.swappiness = $swappiness
EOF
cat > "$work_dir/zram-init" <<EOF
#!/bin/sh
set -eu

size_bytes=$((zram_size_mib * 1024 * 1024))
algorithm='$zram_algorithm'

modprobe zram
[ -r /sys/block/zram0/disksize ] || {
  printf '%s\\n' 'zram0 is not available' >&2
  exit 1
}
[ "\$(cat /sys/block/zram0/disksize)" = 0 ] || {
  printf '%s\\n' 'zram0 is already initialized' >&2
  exit 1
}
printf '%s\\n' "\$algorithm" > /sys/block/zram0/comp_algorithm
printf '%s\\n' "\$size_bytes" > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 5 /dev/zram0
EOF
cat > "$work_dir/zram-config.conf" <<EOF
# Managed by configure-pico-imx7-memory.sh.
[Service]
ExecStart=
ExecStart=$zram_initializer
EOF
cat > "$work_dir/blueman.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Hidden=true
EOF
cat > "$work_dir/firefox-syspref.js" <<'EOF'
// Managed by configure-pico-imx7-memory.sh.
pref("dom.ipc.processCount", 1);
pref("dom.ipc.processCount.webIsolated", 1);
pref("fission.autostart", false);
pref("browser.cache.memory.capacity", 8192);
pref("browser.sessionstore.max_tabs_undo", 0);
pref("browser.sessionhistory.max_total_viewers", 0);
pref("signon.rememberSignons", false);
pref("signon.autofillForms", false);
pref("browser.formfill.enable", false);
pref("layout.spellcheckDefault", 0);
pref("browser.newtabpage.enabled", false);
pref("extensions.pocket.enabled", false);
pref("toolkit.telemetry.enabled", false);
pref("datareporting.healthreport.uploadEnabled", false);
pref("app.normandy.enabled", false);
pref("browser.ping-centre.telemetry", false);
pref("network.prefetch-next", false);
pref("network.dns.disablePrefetch", true);
pref("browser.tabs.unloadOnLowMemory", true);
pref("dom.webnotifications.enabled", false);
pref("webgl.disabled", true);
EOF

install -m 0644 -- "$work_dir/sysctl.conf" "$sysctl_destination"
install -m 0755 -- "$work_dir/zram-init" "$zram_initializer_destination"
install -m 0644 -- "$work_dir/zram-config.conf" "$zram_drop_in_destination"
install -m 0644 -- "$work_dir/blueman.desktop" "$blueman_autostart_destination"
install -m 0644 -- "$work_dir/firefox-syspref.js" "$firefox_preferences_destination"

if [[ "$mode" == image ]]; then
  printf 'staged Pico i.MX7 memory policy under %s\n' "$image_root"
  exit 0
fi

chown ubuntu:ubuntu -- "$blueman_autostart_destination"
sysctl -w "vm.swappiness=$swappiness" >/dev/null
systemctl daemon-reload
systemctl mask --now "${masked_services[@]}"
printf 'configured Firefox low-memory preferences, swappiness=%s, %s MiB %s zram, and disabled unused services; reboot to apply zram\n' \
  "$swappiness" "$zram_size_mib" "$zram_algorithm"
