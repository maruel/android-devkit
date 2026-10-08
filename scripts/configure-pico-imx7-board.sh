#!/usr/bin/env bash
# Stage supported device initialization and service settings in a selected root filesystem.
set -euo pipefail

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
# An image staging tree contains only managed output. Decisions require the real
# image's /etc, supplied separately; never infer service use from an empty tree.
image_root=''
context_root=''
if (($# == 0)); then
  [[ $(id -u) == 0 ]] || fail 'run as root'
elif [[ $# == 4 && $1 == --image-root && $3 == --context-root ]]; then
  image_root=$2
  context_root=$4
  for directory in "$image_root" "$context_root"; do
    [[ $directory == /* && -d $directory && ! -L $directory ]] || fail 'roots must be absolute directories'
  done
else
  fail 'usage: configure-pico-imx7-board.sh [--image-root /path --context-root /actual-image-context]'
fi
for command in awk cat chmod chown dirname find install ln mktemp readlink rm; do
  command -v "$command" >/dev/null || fail "missing executable: $command"
done
if [[ -z $image_root ]]; then
  for command in getent journalctl systemctl usermod; do
    command -v "$command" >/dev/null || fail "missing executable: $command"
  done
fi
for file in passwd group; do
  [[ -f $context_root/etc/$file && ! -L $context_root/etc/$file ]] || fail "missing context /etc/$file"
done
ubuntu_uid=$(awk -F: '$1=="ubuntu" {print $3}' "$context_root/etc/passwd")
ubuntu_gid=$(awk -F: '$1=="ubuntu" {print $4}' "$context_root/etc/passwd")
[[ $ubuntu_uid =~ ^[0-9]+$ && $ubuntu_gid =~ ^[0-9]+$ ]] || fail 'ubuntu account is missing or ambiguous'
for group in audio video; do
  awk -F: -v name="$group" '$1==name {found++} END {exit found!=1}' "$context_root/etc/group" || fail "missing group: $group"
done
has_directives() {
  local file=$1 status
  [[ -r $file && -f $file && ! -L $file ]] || fail "unreadable or unsafe DNS configuration: $file"
  if awk '
    /^[[:space:]]*(#|$)/ {next}
    # These Ubuntu packaging defaults do not assign a DNS or DHCP role.
    FILENAME ~ /\/default\/dnsmasq$/ && /^ENABLED=[01]$/ {next}
    FILENAME ~ /\/default\/dnsmasq$/ && /^CONFIG_DIR=\/etc\/dnsmasq.d,\.dpkg-dist,\.dpkg-old,\.dpkg-new$/ {next}
    {found=1} END {exit !found}' "$file"; then return 0
  else status=$?; [[ $status == 1 ]] || fail "cannot inspect DNS configuration: $file"; return 1; fi
}
work_dir=$(mktemp -d)
trap 'rm -rf -- "$work_dir"' EXIT
mask_dnsmasq=false
# Any active directive is evidence of a configured role, even an include whose
# contents we cannot resolve. Unknown custom startup arguments also preserve it.
if [[ -f $context_root/lib/systemd/system/systemd-resolved.service || -f $context_root/usr/lib/systemd/system/systemd-resolved.service ]]; then
  configured=false
  for directory in "$context_root/etc/dnsmasq.d" "$context_root/etc/systemd/system/dnsmasq.service.d"; do
    if [[ -L $directory ]]; then configured=true
    elif [[ -e $directory ]]; then
      [[ -d $directory && -r $directory && -x $directory ]] || fail "unreadable DNS configuration directory: $directory"
      find "$directory" -type f -print0 > "$work_dir/dns-files" || fail "cannot enumerate DNS configuration: $directory"
      find "$directory" -type l -print > "$work_dir/dns-links" || fail "cannot enumerate DNS links: $directory"
      while IFS= read -r -d '' file; do
        if has_directives "$file"; then configured=true; fi
      done < "$work_dir/dns-files"
      [[ ! -s "$work_dir/dns-links" ]] || configured=true
    fi
  done
  for file in "$context_root/etc/dnsmasq.conf" "$context_root/etc/default/dnsmasq"; do
    if [[ -e $file || -L $file ]]; then
      if [[ -L $file ]] || has_directives "$file"; then configured=true; fi
    fi
  done
  [[ ! -f $context_root/etc/systemd/system/dnsmasq.service ]] || configured=true
  # An existing mask is allowed; other custom symlinks preserve operator intent.
  if [[ -L $context_root/etc/systemd/system/dnsmasq.service && $(readlink "$context_root/etc/systemd/system/dnsmasq.service") != /dev/null ]]; then configured=true; fi
  [[ $configured == true ]] || mask_dnsmasq=true
fi
cat > "$work_dir/device-init" <<'INIT'
#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob
for device in /dev/fb* /dev/mxc_* /dev/video* /dev/galcore /dev/dri/card*; do
  [[ -c $device ]] || continue
  chgrp video "$device"
  chmod 0660 "$device"
done
render_group=video
if getent group render >/dev/null; then render_group=render; fi
for device in /dev/dri/renderD*; do
  [[ -c $device ]] || continue
  chgrp "$render_group" "$device"
  chmod 0660 "$device"
done
for device in /dev/snd/*; do
  [[ -c $device ]] || continue
  chgrp audio "$device"
  chmod 0660 "$device"
done
rfkill unblock wlan
INIT
cat > "$work_dir/device-service" <<'UNIT'
[Service]
Type=oneshot
ExecStart=
ExecStart=/usr/local/sbin/pico-imx7-device-init
RemainAfterExit=yes
UNIT
cat > "$work_dir/journal" <<'JOURNAL'
[Journal]
Storage=persistent
SystemMaxUse=32M
RuntimeMaxUse=8M
JOURNAL
cat > "$work_dir/watchdog" <<'WATCHDOG'
[Manager]
RuntimeWatchdogSec=30s
WATCHDOG
cat > "$work_dir/cheese" <<'CHEESE'
#!/usr/bin/env bash
set -euo pipefail
command -v gsettings >/dev/null || exit 0
schemas=$(gsettings list-schemas)
if ! printf '%s\n' "$schemas" | grep -Fx org.gnome.Cheese >/dev/null; then exit 0; fi
for mode in photo video; do
  gsettings set org.gnome.Cheese "$mode-x-resolution" 1280
  gsettings set org.gnome.Cheese "$mode-y-resolution" 720
done
CHEESE
cat > "$work_dir/cheese-desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Pico i.MX7 Cheese defaults
Exec=/usr/local/bin/pico-imx7-cheese-defaults
OnlyShowIn=XFCE;
Terminal=false
DESKTOP
sources=(device-init device-service journal watchdog cheese cheese-desktop)
destinations=(
  /usr/local/sbin/pico-imx7-device-init
  /etc/systemd/system/tn_init.service.d/10-pico-imx7.conf
  /etc/systemd/journald.conf.d/10-pico-imx7-recovery.conf
  /etc/systemd/system.conf.d/10-pico-imx7-watchdog.conf
  /usr/local/bin/pico-imx7-cheese-defaults
  /home/ubuntu/.config/autostart/pico-imx7-cheese-defaults.desktop
)
for index in "${!sources[@]}"; do
  destination=$image_root${destinations[$index]}
  [[ ! -L $destination && ( ! -e $destination || -f $destination ) ]] || fail "unsafe destination: $destination"
  parent=$(dirname -- "$destination")
  [[ ! -L $parent ]] || fail "unsafe destination directory: $parent"
  install -d -- "$parent"
  mode=0644
  [[ ${sources[$index]} != device-init && ${sources[$index]} != cheese ]] || mode=0755
  install -m "$mode" -- "$work_dir/${sources[$index]}" "$destination"
done
if [[ -n $image_root ]]; then
  awk -F: 'BEGIN {OFS=":"} $1=="audio" || $1=="video" || $1=="render" {
    count=split($4,members,","); found=0
    for(i=1;i<=count;i++) if(members[i]=="ubuntu") found=1
    if(!found) $4=$4 ($4=="" ? "" : ",") "ubuntu"
  } {print}' "$context_root/etc/group" > "$image_root/etc/group"
  chmod 0644 "$image_root/etc/group"
else
  groups=audio,video
  if getent group render >/dev/null; then groups+=,render; fi
  usermod -a -G "$groups" ubuntu
  chown "$ubuntu_uid:$ubuntu_gid" "${destinations[5]}"
fi
if [[ $mask_dnsmasq == true ]]; then
  destination=$image_root/etc/systemd/system/dnsmasq.service
  [[ ! -e $destination || -L $destination ]] || fail "unsafe mask destination: $destination"
  ln -sfn -- /dev/null "$destination"
fi
if [[ -z $image_root ]]; then
  systemctl daemon-reload
  if [[ $mask_dnsmasq == true ]]; then systemctl mask --now dnsmasq.service; systemctl reset-failed dnsmasq.service; fi
  systemctl restart tn_init.service systemd-journald.service
  journalctl --flush
fi
printf 'Configured device permissions, Cheese defaults, recovery policy; unused dnsmasq mask=%s. Watchdog and login groups require next boot/login.\n' "$mask_dnsmasq"
