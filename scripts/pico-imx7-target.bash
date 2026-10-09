# shellcheck disable=SC2154
# Inventory and request data are supplied by the updater prefix, not ambient input.
# Runs as root on the target, prefixed with the shared artifact inventory and
# generated hostname helper by update-pico-imx7-device.sh. No target is implicit.
set -euo pipefail
export LC_ALL=C
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
mode=$1
[[ $(id -u) == 0 ]] || fail 'target operation requires root'
# Serialize remote operations, including read-only boot inspections. Borrowing
# another live operation's mount can otherwise prevent its owner's unmount.
# /run is volatile and root-owned; this lock never changes persistent policy.
command -v flock >/dev/null || fail 'missing target executable: flock'
[[ -d /run && ! -L /run && $(stat -c %u /run) == 0 ]] || fail 'unsafe runtime lock directory'
lock_path=/run/pico-imx7-update.lock
[[ ! -L $lock_path && ( ! -e $lock_path || ( -f $lock_path && $(stat -c %u "$lock_path") == 0 ) ) ]] || fail 'unsafe runtime update lock'
umask 077
exec 9>"$lock_path"
flock -w 30 9 || fail 'another target operation holds the boot/update lock; retry after it completes'
work_dir=$(mktemp -d /tmp/pico-imx7-update.XXXXXX)
boot_mounted=false
boot_path=''
boot_restore_needed=false
boot_original_sha=''
rollback_dtb=''
rollback_uenv=''
managed_temporary=''
pending_temporary=''
boot_rollback_copy=''
boot_rollback_uenv=''
cleanup() {
  [[ -z $managed_temporary ]] || rm -f -- "$managed_temporary"
  [[ -z $pending_temporary ]] || rm -f -- "$pending_temporary"
  if [[ $boot_restore_needed == true ]]; then
    if cp -- "$rollback_dtb" "$boot_path/imx7d-pico-pi.dtb" &&
       cp -- "$rollback_uenv" "$boot_path/uEnv.txt" &&
       [[ $(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb") == "$boot_original_sha" &&
          $(artifact_sha256 "$boot_path/uEnv.txt") == "$(artifact_sha256 "$rollback_uenv")" ]]; then
      rm -f -- "$boot_path/.imx7d-pico-pi.dtb.new" "$boot_path/.uEnv.txt.new"
      sync
    else
      printf 'error: interrupted boot rollback failed; recovery on /dev/mmcblk2p1: DTB=%s uEnv=%s; originals also remain in %s\n' \
        "${boot_rollback_copy#"$boot_path"}" "${boot_rollback_uenv#"$boot_path"}" "$work_dir" >&2
      return 1
    fi
  fi
  [[ -z $boot_rollback_copy ]] || rm -f -- "$boot_rollback_copy"
  [[ -z $boot_rollback_uenv ]] || rm -f -- "$boot_rollback_uenv"
  if [[ $boot_mounted == true ]]; then umount -- "$work_dir/boot"; fi
  rm -rf -- "$work_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
mount_boot() {
  local writable=$1 options source
  boot_path=$(findmnt -rn -S /dev/mmcblk2p1 -o TARGET || [[ $? == 1 ]])
  [[ $boot_path != *$'\n'* ]] || fail 'multiple boot mounts'
  if [[ -n $boot_path ]]; then
    source=$(findmnt -rn -T "$boot_path" -o SOURCE)
    [[ $source == /dev/mmcblk2p1 ]] || fail 'boot mount changed'
    options=$(findmnt -rn -T "$boot_path" -o OPTIONS)
    if [[ $writable == true && ,$options, != *,rw,* ]]; then fail 'boot is already mounted read-only; refusing to remount operator mount'; fi
  else
    boot_path=$work_dir/boot
    mkdir -p -- "$boot_path"
    options=ro
    [[ $writable == false ]] || options=rw
    mount -t vfat -o "$options" -- /dev/mmcblk2p1 "$boot_path"
    boot_mounted=true
  fi
}
release_boot() {
  if [[ $boot_mounted == true ]]; then umount -- "$work_dir/boot"; boot_mounted=false; fi
  boot_path=''
}
pending_file=/var/lib/pico-imx7-update/pending-reboot
pending_status=none
pending_marked=false
check_pending() {
  local uid=$1 current_boot
  local -a lines=()
  pending_status=none
  [[ -e $pending_file || -L $pending_file ]] || return 0
  [[ -f $pending_file && ! -L $pending_file && $(stat -c '%u:%g:%a' "$pending_file") == 0:0:600 &&
     $(stat -c %s "$pending_file") -le 256 ]] || fail 'unsafe pending reboot marker'
  mapfile -t lines < "$pending_file"
  [[ ${#lines[@]} == 3 && ${lines[0]} == "uid=$uid" && ${lines[1]} == "record=$expected_record" &&
     ${lines[2]} =~ ^boot_id=[a-f0-9-]{36}$ ]] || fail 'pending reboot identity/record mismatch; finish the previous recorded update first'
  current_boot=$(cat /proc/sys/kernel/random/boot_id)
  pending_status=new_boot
  [[ ${lines[2]#boot_id=} != "$current_boot" ]] || pending_status=same_boot
}
mark_pending() {
  [[ $pending_marked == false ]] || return 0
  [[ ! -L /var/lib/pico-imx7-update ]] || fail 'unsafe pending state directory'
  install -d -m 0700 -o root -g root /var/lib/pico-imx7-update
  pending_temporary=$(mktemp /var/lib/pico-imx7-update/.pending.XXXXXX)
  printf 'uid=%s\nrecord=%s\nboot_id=%s\n' "$expected_uid" "$expected_record" "$(cat /proc/sys/kernel/random/boot_id)" > "$pending_temporary"
  chmod 0600 "$pending_temporary"
  mv -T -- "$pending_temporary" "$pending_file"
  pending_temporary=''
  sync -f "$pending_file"
  pending_status=same_boot
  pending_marked=true
}
board_preflight() {
  local model identity uid release root_source wifi night_option_present
  for executable in awk bash cat cmp cut date depmod dpkg-query find findmnt getent grep hostname install journalctl ln modinfo mount mv pgrep readlink rm runuser sed sha256sum sort stat sync sysctl systemctl tail tar timeout tr umount usermod wc; do
    command -v "$executable" >/dev/null || fail "missing target executable: $executable"
  done
  [[ $selected_night_exposure == true || $selected_night_exposure == false ]] || fail 'invalid selected camera module capability'
  if [[ $selected_night_exposure == false && -e /etc/modprobe.d/ov5645-night.conf ]]; then
    night_option_present=$(awk '
      {
        sub(/#.*/, "")
        continued=sub(/\\[[:space:]]*$/, "")
        logical=logical $0
        if (continued) next
        sub(/^[[:space:]]+/, "", logical)
        count=split(logical, words, /[[:space:]]+/)
        gsub(/-/, "_", words[2])
        if (words[1] == "options" && words[2] == "ov5645_camera_mipi_v2") {
          for (i=3; i<=count; i++) {
            option_name=words[i]
            sub(/^"/, "", option_name)
            sub(/=.*/, "", option_name)
            gsub(/-/, "_", option_name)
            if (option_name == "night_max_exposure_ms" && index(words[i], "=")) found=1
          }
        }
        logical=""
      }
      END {print found ? "true" : "false"}
    ' /etc/modprobe.d/ov5645-night.conf) || fail 'cannot inspect OV5645 night configuration'
    if [[ $night_option_present == true ]]; then
      fail 'selected OV5645 module lacks night_max_exposure_ms; rebuild/install a compatible module or remove /etc/modprobe.d/ov5645-night.conf opt-in before using prebuilt modules'
    fi
  fi
  model=$(tr -d '\0' < /proc/device-tree/model)
  [[ $model == "$BOARD_MODEL" ]] || fail "unsupported board model: $model"
  [[ $(uname -r) == "$TARGET_RELEASE" ]] || fail 'unsupported running kernel'
  # Read only the two standard OS identity fields, without executing os-release.
  release=$(awk -F= '$1=="ID" || $1=="VERSION_ID" {gsub(/"/,"",$2); print $1"="$2}' /etc/os-release)
  [[ $release == $'ID=ubuntu\nVERSION_ID=22.04' || $release == $'VERSION_ID=22.04\nID=ubuntu' ]] || fail 'expected Ubuntu 22.04'
  root_source=$(findmnt -rn -o SOURCE /)
  [[ $root_source == /dev/mmcblk2p2 ]] || fail "unexpected root filesystem: $root_source"
  identity=$(pico_identity --identity)
  printf '%s\n' "$identity"
  uid=${identity%%$'\n'*}; uid=${uid#uid=}
  if [[ -n ${expected_uid:-} ]]; then [[ $uid == "$expected_uid" ]] || fail 'full UID changed since fleet preflight'; fi
  check_pending "$uid"
  printf 'pending_reboot=%s\n' "$pending_status"
  target_ip=${PICO_SSH_IP:?}
  [[ $target_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'SSH must use IPv4'
  printf 'ip=%s\nmodel=%s\ncurrent_hostname=%s\n' "$target_ip" "$model" "$(hostname)"
  mount_boot false
  [[ -f $boot_path/zImage && ! -L $boot_path/zImage ]] || fail 'missing boot kernel'
  [[ $(artifact_sha256 "$boot_path/zImage") == "$BOOT_KERNEL_SHA256" ]] || fail 'boot kernel identity differs from inspected image'
  [[ -f $boot_path/imx7d-pico-pi.dtb && ! -L $boot_path/imx7d-pico-pi.dtb && -f $boot_path/uEnv.txt && ! -L $boot_path/uEnv.txt ]] || fail 'unsafe boot configuration'
  printf 'dtb_sha256=%s\n' "$(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb")"
  wifi=$(awk -F= '$1=="wifi_module" {print $2}' "$boot_path/uEnv.txt")
  [[ $wifi == brcm || $wifi == qca ]] || fail 'expected exactly one supported wifi_module selection'
  printf 'wifi_selection=%s\n' "$wifi"
  release_boot
}
failed_units() { systemctl --failed --no-legend --plain | awk '{print $1}' | sort; }
context_export() {
  # Only context consumed by policy generators; exclude network credentials,
  # shadow, SSH keys, and unrelated configuration.
  local path
  local -a paths=(etc/passwd etc/group)
  for path in etc/dnsmasq.conf etc/default/dnsmasq etc/dnsmasq.d etc/systemd/system/dnsmasq.service etc/systemd/system/dnsmasq.service.d lib/systemd/system/systemd-resolved.service usr/lib/systemd/system/systemd-resolved.service; do
    if [[ -e /$path || -L /$path ]]; then paths+=("$path"); fi
  done
  local -a absolute_paths=()
  for path in "${paths[@]}"; do absolute_paths+=("/$path"); done
  find "${absolute_paths[@]}" -type f -printf '%s\n' | awk '{count++; total+=$1} END {exit count>256 || total>2097152}' || fail 'policy context exceeds the 256-file/2-MiB bound'
  tar -C / -cf - -- "${paths[@]}"
}
file_matches() {
  local path=$1 digest=$2 permissions=$3 owner=$4
  [[ -f $path && ! -L $path ]] &&
    [[ $(artifact_sha256 "$path") == "$digest" && $(stat -c '%a' -- "$path") == "$permissions" && $(stat -c '%u:%g' -- "$path") == "$owner" ]]
}
safe_parent() {
  local path=$1 parent
  [[ $path == /* && $path != *'/../'* && $path != *'/./'* && $path != *'//'* ]] || fail 'unsafe managed path'
  parent=${path%/*}
  while [[ $parent != / && -n $parent ]]; do
    if [[ $parent == /lib && -L /lib && $(readlink /lib) == usr/lib ]]; then parent=/usr/lib; continue; fi
    [[ ! -L $parent ]] || fail "symlinked managed parent: $parent"
    [[ ! -e $parent || -d $parent ]] || fail "non-directory managed parent: $parent"
    parent=${parent%/*}
  done
}
safe_destination() {
  safe_parent "$1"
  [[ ! -L $1 && ( ! -e $1 || -f $1 ) ]] || fail "unsafe managed destination: $1"
}
policy_plan() {
  local kind digest permissions owner path actual
  differences=0
  while IFS=$'\t' read -r kind digest permissions owner path; do
    [[ -n $kind ]] || continue
    case $kind in
      F)
        safe_destination "$path"
        if file_matches "$path" "$digest" "$permissions" "$owner"; then continue; fi
        actual=missing
        [[ ! -f $path ]] || actual=$(artifact_sha256 "$path")
        printf 'change=file %s current=%s expected=%s mode=%s owner=%s\n' "$path" "$actual" "$digest" "$permissions" "$owner"
        ;;
      L)
        safe_parent "$path"
        [[ ! -e $path || -L $path ]] || fail "unsafe managed link: $path"
        if [[ -L $path && $(readlink -- "$path") == "$digest" ]]; then continue; fi
        printf 'change=link %s -> %s\n' "$path" "$digest"
        ;;
      G)
        actual=$(getent group "$path")
        [[ -n $actual ]] || fail "missing group: $path"
        if [[ ,${actual##*:}, == *,ubuntu,* ]]; then continue; fi
        printf 'change=group ubuntu -> %s\n' "$path"
        ;;
      *) fail 'unknown manifest entry' ;;
    esac
    differences=$((differences+1))
  done <<< "$plan_text"
  printf 'managed_differences=%d\n' "$differences"
}
boot_plan() {
  local current wifi
  boot_differences=0
  mount_boot false
  current=$(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb")
  wifi=$(awk -F= '$1=="wifi_module" {print $2}' "$boot_path/uEnv.txt")
  [[ $wifi == qca || $wifi == brcm ]] || fail 'expected exactly one supported wifi_module selection'
  release_boot
  if [[ $current != "$expected_dtb" ]]; then
    printf 'change=boot_dtb current=%s expected=%s\n' "$current" "$expected_dtb"
    boot_differences=$((boot_differences+1))
  fi
  if [[ $wifi != brcm ]]; then
    printf 'change=boot_selection current=%s expected=brcm\n' "$wifi"
    boot_differences=$((boot_differences+1))
  fi
  printf 'boot_differences=%d\n' "$boot_differences"
}
inspect_live() {
  local index path hash
  printf 'failed_units_begin\n'; failed_units; printf 'failed_units_end\n'
  for index in "${!module_names[@]}"; do
    path=/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}
    hash=missing
    [[ ! -f $path ]] || hash=$(artifact_sha256 "$path")
    printf 'installed_module=%s %s\n' "${module_names[$index]}" "$hash"
  done
  printf 'swappiness=%s\nzram_bytes=%s\nzram_algorithm=%s\n' "$(cat /proc/sys/vm/swappiness)" "$(cat /sys/block/zram0/disksize)" "$(cat /sys/block/zram0/comp_algorithm)"
  awk '$1=="CmaTotal:" {print "cma_kib="$2}' /proc/meminfo
  printf 'watchdog_pid1_fds=%s\n' "$(find /proc/1/fd -maxdepth 1 -type l -lname '*watchdog*' -printf '%l ' 2>/dev/null)"
  printf 'third_party_source=%s\n' "$(find /etc/apt/sources.list.d -maxdepth 1 -type f -name '*vivaldi*' -printf '%f ' 2>/dev/null)"
  dpkg-query -W -f='package=${binary:Package} ${db:Status-Abbrev}\n' 'vivaldi*' netsurf-gtk 2>/dev/null || [[ $? == 1 ]]
}
session_run() {
  local uid session_pid entry display='' authority='' bus=''
  uid=$(id -u ubuntu)
  session_pid=$(pgrep -u "$uid" -x xfce4-session)
  [[ $session_pid =~ ^[0-9]+$ ]] || fail 'expected one running ubuntu Xfce session'
  while IFS= read -r -d '' entry; do
    case $entry in DISPLAY=*) display=${entry#*=};; XAUTHORITY=*) authority=${entry#*=};; DBUS_SESSION_BUS_ADDRESS=*) bus=${entry#*=};; esac
  done < "/proc/$session_pid/environ"
  [[ -n $display && -n $bus ]] || fail 'Xfce session lacks display or bus'
  [[ -n $authority ]] || authority=/home/ubuntu/.Xauthority
  runuser -u ubuntu -- env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/home/ubuntu DISPLAY="$display" XAUTHORITY="$authority" DBUS_SESSION_BUS_ADDRESS="$bus" "$@"
}
verify_live() {
  local identity hostname_expected watchdog_pid journal_pid path index current failed state kind digest permissions owner format
  policy_plan
  ((differences == 0)) || fail 'managed files, links, or groups differ'
  boot_plan
  ((boot_differences == 0)) || fail 'boot policy differs'
  identity=$(pico_identity --identity)
  hostname_expected=${identity##*$'\n'}; hostname_expected=${hostname_expected#hostname=}
  [[ $(hostname) == "$hostname_expected" && $(cat /etc/hostname) == "$hostname_expected" ]] || fail 'hostname not applied'
  [[ $(cat /proc/sys/vm/swappiness) == 10 && $(cat /sys/block/zram0/disksize) == 201326592 && $(cat /sys/block/zram0/comp_algorithm) == *'[lzo-rle]'* ]] || fail 'live memory policy differs'
  [[ $(awk '$1=="CmaTotal:" {print $2}' /proc/meminfo) == 196608 ]] || fail 'CMA must remain 192 MiB'
  [[ -d /var/log/journal && $(systemctl is-active systemd-journald.service) == active ]] || fail 'persistent journal unavailable'
  journal_pid=$(systemctl show -p MainPID --value systemd-journald.service)
  [[ $journal_pid =~ ^[1-9][0-9]*$ && -n $(find "/proc/$journal_pid/fd" -maxdepth 1 -type l -lname '/var/log/journal/*' -printf '%l') ]] || fail 'journald has no open persistent journal'
  watchdog_pid=$(find /proc/1/fd -maxdepth 1 -type l -lname '*watchdog*' -printf '%l\n')
  [[ -n $watchdog_pid ]] || fail 'PID 1 does not own the hardware watchdog'
  [[ $(systemctl show -p RuntimeWatchdogUSec --value) == 30s ]] || fail 'live watchdog timeout differs'
  printf 'watchdog_active_owner=PID1 live_timeout=30s\n'
  [[ $(systemctl is-active tn_init.service) == active ]] || fail 'device initializer not active'
  while IFS=$'\t' read -r kind digest permissions owner path; do
    [[ $kind == L && $digest == /dev/null ]] || continue
    state=$(systemctl is-active "${path##*/}" || true)
    [[ $state != active && $state != activating ]] || fail "masked service remains active: ${path##*/}"
  done <<< "$plan_text"
  getent hosts archive.ubuntu.com >/dev/null || fail 'DNS resolution failed'
  session_run /usr/local/bin/pico-imx7-plain-background --check
  # The session shell expands this fixed script.
  # shellcheck disable=SC2016
  session_run bash -c 'if gsettings list-schemas | grep -Fx org.gnome.Cheese >/dev/null; then for mode in photo video; do [[ $(gsettings get org.gnome.Cheese "$mode-x-resolution") == 1280 && $(gsettings get org.gnome.Cheese "$mode-y-resolution") == 720 ]] || exit 1; done; fi'
  for index in "${!module_names[@]}"; do
    path=/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}
    [[ $(modinfo -F vermagic "$path") == "$TARGET_VERMAGIC" ]] || fail "installed literal module identity differs: $path"
    [[ $(modinfo -n "${module_names[$index]%.ko}") == "$path" ]] || fail "module resolution differs: $path"
    awk -F: -v expected="${module_destinations[$index]}" '$1==expected {found++} END {exit found!=1}' "/lib/modules/$TARGET_RELEASE/modules.dep" || fail "missing/ambiguous module dependency metadata: $path"
  done
  failed=$(failed_units)
  while IFS= read -r current; do
    [[ -z $current ]] && continue
    if ! grep -Fx -- "$current" <<< "$initial_failures" >/dev/null; then fail "new failed service: $current"; fi
    printf 'preexisting_failed_unit=%s\n' "$current"
  done <<< "$failed"
  if [[ ${camera_test:-false} == true ]]; then
    command -v v4l2-ctl >/dev/null || fail 'camera acceptance requires v4l2-ctl'
    # The pinned mx6s S_FMT handler validates the requested supported fourcc,
    # but stores only width/height/sizeimage/field in csi_dev->pix. G_FMT copies
    # that struct and therefore reports an empty fourcc and zero bytesperline.
    # Query dimensions and size on the same open that successfully sets YUYV
    # and captures; never infer pixel-format failure from that omitted field.
    timeout --signal=TERM --kill-after=5s 60 v4l2-ctl -d /dev/video1 --set-fmt-video=width=1280,height=720,pixelformat=YUYV --get-fmt-video --stream-mmap=4 --stream-count=300 --stream-to=/dev/null > "$work_dir/camera-format"
    format=$(cat "$work_dir/camera-format")
    [[ $(awk -F: '/Width\/Height/ {gsub(/[[:space:]]/,"",$2); print $2}' <<< "$format") == 1280/720 &&
       $(awk -F: '/Size Image/ {gsub(/[[:space:]]/,"",$2); print $2}' <<< "$format") == 1843200 ]] || fail 'camera did not accept exact 1280x720 frame dimensions and size'
    # Reopen with an explicit format; driver metadata omissions also apply here.
    timeout --signal=TERM --kill-after=5s 15 v4l2-ctl -d /dev/video1 --set-fmt-video=width=1280,height=720,pixelformat=YUYV --get-fmt-video --stream-mmap=4 --stream-count=1 --stream-to=/dev/null > "$work_dir/camera-reopen-format"
    format=$(cat "$work_dir/camera-reopen-format")
    [[ $(awk -F: '/Width\/Height/ {gsub(/[[:space:]]/,"",$2); print $2}' <<< "$format") == 1280/720 &&
       $(awk -F: '/Size Image/ {gsub(/[[:space:]]/,"",$2); print $2}' <<< "$format") == 1843200 ]] || fail 'camera reopen format differs'
    printf 'camera_acceptance=300 frames 1280x720 YUYV and clean reopen\n'
  fi
  if [[ $pending_status == same_boot ]]; then fail 'boot-dependent changes still require a reboot'; fi
  if [[ $pending_status == new_boot ]]; then rm -f -- "$pending_file"; fi
  printf 'verification_boot_id=%s\n' "$(cat /proc/sys/kernel/random/boot_id)"
  printf 'verification=PASS\n'
}
apply_update() {
  local kind digest permissions owner path parent changed=false reboot=false systemd_changed=false journal_changed=false device_changed=false link_service
  board_preflight
  [[ $pending_status != same_boot ]] || reboot=true
  policy_plan
  [[ -f $payload/boot/imx7d-pico-pi.dtb && ! -L $payload/boot/imx7d-pico-pi.dtb &&
     $(artifact_sha256 "$payload/boot/imx7d-pico-pi.dtb") == "$expected_dtb" ]] || fail 'transferred DTB identity mismatch'
  # Validate the complete transferred content before the first persistent write.
  while IFS=$'\t' read -r kind digest permissions owner path; do
    [[ $kind == F ]] || continue
    [[ -f $payload/root$path && ! -L $payload/root$path && $(artifact_sha256 "$payload/root$path") == "$digest" ]] || fail "staged content differs: $path"
  done <<< "$plan_text"
  while IFS=$'\t' read -r kind digest permissions owner path; do
    case $kind in
      F)
        if file_matches "$path" "$digest" "$permissions" "$owner"; then continue; fi
        safe_destination "$path"
        [[ $(artifact_sha256 "$payload/root$path") == "$digest" ]] || fail "staged content differs: $path"
        if [[ ! -f $path || $(artifact_sha256 "$path") != "$digest" ]]; then mark_pending; reboot=true; fi
        parent=${path%/*}
        install -d -- "$parent"
        managed_temporary=$(mktemp "$parent/.pico-imx7-managed.XXXXXX")
        install -m "$permissions" -o "${owner%:*}" -g "${owner#*:}" -- "$payload/root$path" "$managed_temporary"
        file_matches "$managed_temporary" "$digest" "$permissions" "$owner" || fail "temporary file verification failed: $path"
        mv -T -- "$managed_temporary" "$path"
        managed_temporary=''
        file_matches "$path" "$digest" "$permissions" "$owner" || fail "installed file verification failed: $path"
        changed=true
        [[ $path != /etc/systemd/* ]] || systemd_changed=true
        [[ $path != /etc/systemd/journald.conf.d/* ]] || journal_changed=true
        [[ $path != /usr/local/sbin/pico-imx7-device-init && $path != /etc/systemd/system/tn_init.service.d/* ]] || device_changed=true
        ;;
      L)
        if [[ -L $path && $(readlink -- "$path") == "$digest" ]]; then continue; fi
        mark_pending
        install -d -- "${path%/*}"
        ln -sfn -- "$digest" "$path"
        changed=true; reboot=true; systemd_changed=true
        if [[ $digest == /dev/null ]]; then
          link_service=${path##*/}
          # Stopping an existing failed unit is safe; no failure is concealed.
          if [[ $(systemctl is-active "$link_service" || true) == active ]]; then systemctl stop "$link_service"; fi
        fi
        ;;
      G)
        if [[ ,$(getent group "$path" | cut -d: -f4), == *,ubuntu,* ]]; then continue; fi
        mark_pending
        usermod -a -G "$path" ubuntu
        changed=true; reboot=true
        ;;
    esac
  done <<< "$plan_text"
  if [[ $systemd_changed == true ]]; then systemctl daemon-reload; fi
  if [[ $device_changed == true ]]; then systemctl restart tn_init.service; fi
  if [[ $journal_changed == true ]]; then
    install -d -m 2755 -o root -g systemd-journal /var/log/journal
    systemctl restart systemd-journald.service
    journalctl --flush
  fi
  if [[ $changed == true ]]; then
    depmod -a "$TARGET_RELEASE"
  fi
  policy_plan
  ((differences == 0)) || fail 'post-install manifest differs'
  local desired_hostname
  desired_hostname=$(pico_identity --identity)
  desired_hostname=${desired_hostname##*$'\n'}; desired_hostname=${desired_hostname#hostname=}
  if [[ $(hostname) != "$desired_hostname" || $(cat /etc/hostname) != "$desired_hostname" ]]; then
    mark_pending
    /usr/local/sbin/pico-imx7-hostname
    changed=true; reboot=true
  fi
  sysctl -w vm.swappiness=10 >/dev/null
  if ! session_run /usr/local/bin/pico-imx7-plain-background --check; then session_run /usr/local/bin/pico-imx7-plain-background; changed=true; fi
  session_run /usr/local/bin/pico-imx7-cheese-defaults
  if [[ $(cat /sys/block/zram0/disksize) != 201326592 || $(cat /sys/block/zram0/comp_algorithm) != *'[lzo-rle]'* ]]; then reboot=true; fi
  if [[ -z $(find /proc/1/fd -maxdepth 1 -type l -lname '*watchdog*' -printf '%l') ]]; then reboot=true; fi
  update_boot
  if [[ $boot_changed == true ]]; then changed=true; reboot=true; fi
  if [[ $install_netsurf == true ]]; then install_browser; fi
  [[ ! -f /var/run/reboot-required ]] || reboot=true
  printf 'apply_changed=%s\nreboot_needed=%s\n' "$changed" "$reboot"
}
update_boot() {
  local current wifi desired_uenv
  boot_changed=false
  mount_boot false
  current=$(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb")
  wifi=$(awk -F= '$1=="wifi_module" {print $2}' "$boot_path/uEnv.txt")
  [[ $wifi == qca || $wifi == brcm ]] || fail 'expected exactly one supported wifi_module selection'
  if [[ $current == "$expected_dtb" && $wifi == brcm ]]; then release_boot; return; fi
  rollback_dtb=$work_dir/old.dtb
  rollback_uenv=$work_dir/old.uEnv.txt
  cp -- "$boot_path/imx7d-pico-pi.dtb" "$rollback_dtb"
  cp -- "$boot_path/uEnv.txt" "$rollback_uenv"
  desired_uenv=$work_dir/uEnv.txt
  sed 's/^wifi_module=qca$/wifi_module=brcm/' "$rollback_uenv" > "$desired_uenv"
  [[ $(awk -F= '$1=="wifi_module" {print $2}' "$desired_uenv") == brcm ]] || fail 'cannot prepare Broadcom boot selection'
  release_boot
  mount_boot true
  [[ $(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb") == "$current" &&
     $(artifact_sha256 "$boot_path/uEnv.txt") == "$(artifact_sha256 "$rollback_uenv")" ]] || fail 'boot files changed concurrently before replacement'
  # These copies live on the explicit boot partition only during replacement.
  if [[ $current != "$expected_dtb" ]]; then
    boot_rollback_copy=$(mktemp "$boot_path/.imx7d-pico-pi.dtb.rollback.XXXXXX")
    cp -- "$boot_path/imx7d-pico-pi.dtb" "$boot_rollback_copy"
    [[ $(artifact_sha256 "$boot_rollback_copy") == "$current" ]] || fail "boot rollback copy verification failed: $boot_rollback_copy"
  fi
  if [[ $wifi != brcm ]]; then
    boot_rollback_uenv=$(mktemp "$boot_path/.uEnv.txt.rollback.XXXXXX")
    cp -- "$boot_path/uEnv.txt" "$boot_rollback_uenv"
    [[ $(artifact_sha256 "$boot_rollback_uenv") == "$(artifact_sha256 "$rollback_uenv")" ]] || fail "boot rollback copy verification failed: $boot_rollback_uenv"
  fi
  mark_pending
  boot_original_sha=$current
  boot_restore_needed=true
  # Guard failures explicitly so rollback completes before EXIT unmounts.
  if {
    if [[ $current != "$expected_dtb" ]]; then
      cp -- "$payload/boot/imx7d-pico-pi.dtb" "$boot_path/.imx7d-pico-pi.dtb.new" &&
        mv -- "$boot_path/.imx7d-pico-pi.dtb.new" "$boot_path/imx7d-pico-pi.dtb";
    fi
    if [[ $wifi != brcm ]]; then
      cp -- "$desired_uenv" "$boot_path/.uEnv.txt.new" && mv -- "$boot_path/.uEnv.txt.new" "$boot_path/uEnv.txt";
    fi
    [[ $(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb") == "$expected_dtb" &&
       $(artifact_sha256 "$boot_path/uEnv.txt") == "$(artifact_sha256 "$desired_uenv")" ]]
  }; then
    sync
    boot_changed=true
    boot_restore_needed=false
    [[ -z $boot_rollback_copy ]] || rm -f -- "$boot_rollback_copy"
    boot_rollback_copy=''
    [[ -z $boot_rollback_uenv ]] || rm -f -- "$boot_rollback_uenv"
    boot_rollback_uenv=''
  else
    cp -- "$rollback_dtb" "$boot_path/imx7d-pico-pi.dtb"
    cp -- "$rollback_uenv" "$boot_path/uEnv.txt"
    rm -f -- "$boot_path/.imx7d-pico-pi.dtb.new" "$boot_path/.uEnv.txt.new"
    [[ $(artifact_sha256 "$boot_path/imx7d-pico-pi.dtb") == "$current" &&
       $(artifact_sha256 "$boot_path/uEnv.txt") == "$(artifact_sha256 "$rollback_uenv")" ]] || fail "boot rollback verification failed; recovery on /dev/mmcblk2p1: DTB=${boot_rollback_copy#"$boot_path"} uEnv=${boot_rollback_uenv#"$boot_path"}"
    sync
    boot_restore_needed=false
    [[ -z $boot_rollback_copy ]] || rm -f -- "$boot_rollback_copy"
    boot_rollback_copy=''
    [[ -z $boot_rollback_uenv ]] || rm -f -- "$boot_rollback_uenv"
    boot_rollback_uenv=''
    fail 'boot update failed and original files restored'
  fi
  release_boot
}
install_browser() {
  local source=/etc/apt/sources.list.d/vivaldi.list status
  printf 'package_inventory_begin\n'
  dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'vivaldi*' netsurf-gtk 2>/dev/null || [[ $? == 1 ]]
  printf 'package_inventory_end\n'
  # Disable only a known standalone apt source, and only with no installed
  # Vivaldi package. Other filenames, deb822 sources, and mixed files survive.
  if [[ -f $source && ! -L $source ]] &&
      ! dpkg-query -W -f='${db:Status-Abbrev}\n' 'vivaldi*' 2>/dev/null | grep -q '^ii'; then
    if awk '
      /^[[:space:]]*(#|$)/ {next}
      /^deb (\[arch=armhf\] )?https?:\/\/repo\.vivaldi\.com\/stable\/deb\/ stable main$/ {found++; next}
      {unknown++} END {exit !(found==1 && unknown==0)}' "$source"; then
      [[ ! -e $source.disabled-by-pico-imx7 ]] || fail 'Vivaldi disabled-source destination exists'
      mv -- "$source" "$source.disabled-by-pico-imx7"
      printf 'disabled_unused_source=vivaldi.list\n'
    fi
  fi
  # Remote timeout belongs to this process group, so local SSH cancellation
  # cannot leave apt running without a finite deadline.
  local apt_log=$work_dir/apt.log
  if timeout --signal=TERM --kill-after=10s 360 env DEBIAN_FRONTEND=noninteractive apt-get -o APT::Update::Error-Mode=any -o DPkg::Lock::Timeout=30 update > "$apt_log" 2>&1 &&
     timeout --signal=TERM --kill-after=10s 360 env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=30 install -y --no-install-recommends netsurf-gtk >> "$apt_log" 2>&1; then
    printf 'netsurf_installation=verified\n'
  else
    status=$?
    printf 'apt_failure_log_begin\n'
    tail -c 65536 -- "$apt_log"
    printf '\napt_failure_log_end\n'
    fail "authenticated package setup failed (status $status)"
  fi
}
case $mode in
  --context) context_export ;;
  --inspect) board_preflight; inspect_live ;;
  --plan) board_preflight; policy_plan; boot_plan ;;
  --verify) board_preflight; verify_live ;;
  --apply) apply_update ;;
  *) fail 'unknown target operation' ;;
esac
