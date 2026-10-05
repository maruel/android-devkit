#!/usr/bin/env bash
set -euo pipefail

# Stage the same hardware-derived identity policy in an image or an existing board.
image_root=''
if (($# == 0)); then
  [[ "$(id -u)" == 0 ]] || { printf '%s\n' 'Run as root.' >&2; exit 1; }
elif [[ $# == 2 && $1 == --image-root && $2 == /* && -d $2 && ! -L $2 ]]; then
  image_root="$2"
else
  printf '%s\n' 'usage: configure-pico-imx7-hostname.sh [--image-root /absolute/path]' >&2
  exit 2
fi
readonly image_root

for command in cat chmod install ln mkdir; do
  command -v "$command" >/dev/null || { printf 'Missing executable: %s\n' "$command" >&2; exit 1; }
done
if [[ -z "$image_root" ]]; then
  command -v systemctl >/dev/null
fi

initializer="$image_root/usr/local/sbin/pico-imx7-hostname"
service="$image_root/etc/systemd/system/pico-imx7-hostname.service"
readonly initializer service
install -d -- "$(dirname -- "$initializer")" "$(dirname -- "$service")"
for destination in "$initializer" "$service"; do
  [[ ! -L "$destination" && ( ! -e "$destination" || -f "$destination" ) ]] || {
    printf 'Unsafe destination: %s\n' "$destination" >&2
    exit 1
  }
done

cat > "$initializer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Use the ARM kernel's Serial field; never substitute a network or image identity.
if ! serial="$(awk '
  $1 == "Serial" {
    if ($2 != ":" || NF != 3) exit 1
    count++
    serial = tolower($3)
  }
  END {
    if (count != 1) exit 1
    print serial
  }
' /proc/cpuinfo)"; then
  printf '%s\n' 'Expected one valid Serial field in /proc/cpuinfo.' >&2
  exit 1
fi
[[ "$serial" =~ ^[0-9a-f]{16}$ && "$serial" != 0000000000000000 ]] || {
  printf '%s\n' 'Serial in /proc/cpuinfo must be a nonzero 16-digit hexadecimal value.' >&2
  exit 1
}
new_hostname="technexion-${serial: -4}"
for destination in /etc/hostname /etc/hosts; do
  [[ -f "$destination" && ! -L "$destination" ]] || {
    printf 'Expected a regular file: %s\n' "$destination" >&2
    exit 1
  }
done
old_hostname="$(cat /etc/hostname)"
hosts_temporary="$(mktemp /etc/.pico-imx7-hosts.XXXXXX)"
trap 'rm -f -- "$hosts_temporary"' EXIT
# Keep unrelated mappings and aliases; replace only the local hostname token.
awk -v old="$old_hostname" -v new="$new_hostname" '
  $1 == "127.0.1.1" {
    line = "127.0.1.1\t" new
    for (i = 2; i <= NF; i++) {
      if (substr($i, 1, 1) == "#") {
        for (; i <= NF; i++) line = line " " $i
        break
      }
      if ($i != old && $i != new) line = line " " $i
    }
    print line
    found = 1
    next
  }
  { print }
  END { if (!found) print "127.0.1.1\t" new }
' /etc/hosts > "$hosts_temporary"
chmod --reference=/etc/hosts "$hosts_temporary"
chown --reference=/etc/hosts "$hosts_temporary"
if ! cmp -s -- "$hosts_temporary" /etc/hosts; then
  mv -T -- "$hosts_temporary" /etc/hosts
fi
if [[ "$old_hostname" != "$new_hostname" ]]; then
  printf '%s\n' "$new_hostname" > /etc/hostname
fi
hostname "$new_hostname"
printf 'Hostname: %s\n' "$new_hostname"
EOF
chmod 0755 -- "$initializer"

# Validate and apply the board identity before enabling any boot dependencies.
if [[ -z "$image_root" ]]; then
  "$initializer"
fi

cat > "$service" <<'EOF'
[Unit]
Description=Set Pico i.MX7 hardware-derived hostname before networking
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target network-pre.target NetworkManager.service avahi-daemon.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/pico-imx7-hostname
RemainAfterExit=yes

[Install]
WantedBy=sysinit.target
RequiredBy=NetworkManager.service avahi-daemon.service
EOF
chmod 0644 -- "$service"
for dependency in sysinit.target.wants NetworkManager.service.requires avahi-daemon.service.requires; do
  directory="$image_root/etc/systemd/system/$dependency"
  install -d -- "$directory"
  destination="$directory/pico-imx7-hostname.service"
  [[ ! -e "$destination" || -L "$destination" ]] || {
    printf 'Unsafe service link: %s\n' "$destination" >&2
    exit 1
  }
  ln -sfn -- ../pico-imx7-hostname.service "$destination"
done
if [[ -z "$image_root" ]]; then
  systemctl daemon-reload
  printf '%s\n' 'Hostname policy installed; reboot before using discovery or DHCP under the new name.'
else
  printf 'Staged hostname policy under %s\n' "$image_root"
fi
