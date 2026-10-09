#!/usr/bin/env bash
# Inspect or update explicit boards with validated artifacts and bounded camera acceptance.
# Remote SSH shells expand fixed quoted command templates below.
# shellcheck disable=SC2016
set -euo pipefail
export LC_ALL=C
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=${script_dir%/scripts}
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'HELP'
usage: update-device.sh --target ubuntu@IPv4-or-host [--target ...] [options]

Default: inspect every explicit target and report the verified differential;
no persistent target or artifact changes. All boards pass preflight and fleet
identity checks before --apply writes any board. No implicit target is used.

  --apply                  Install the supported recorded artifacts and policy
  --check                  Read-only inventory (the default)
  --module-build /path     Validated build (default: tracked seven-module set)
  --firmware-dir /path     Verified AP6335 files (default: artifacts/firmware/ap6335)
  --install-netsurf        Authenticated package setup (requires --apply)
  --camera-test            Finite 300-frame 720p acceptance (requires --apply)
  --help                   Show this help

--apply may replace custom modules with the explicitly selected recorded set;
inspect first. Boot DTB replacement uses a temporary rollback copy on mmcblk2p1, deleted
after verified replacement or verified restoration. Configuration backups are
not retained.
Reboot occurs only when needed, waits at least 40s, and reconnects by pinned IP.
Apply evidence and bounded failure logs are saved under artifacts/target-updates.
Fetch firmware first with ./fetch-ap6335-firmware.sh if it is absent.
HELP
}
apply=false; install_netsurf=false; camera_test=false
module_build=$repo_dir/prebuilt/pico-imx7/ubuntu-22.04-5.15.71
firmware_dir=$repo_dir/artifacts/firmware/ap6335
declare -a targets=() ips=() uids=() hostnames=()
while (($#)); do
  case $1 in
    --target|--module-build|--firmware-dir)
      (($# >= 2)) || fail "missing value for $1"
      case $1 in --target) targets+=("$2");; --module-build) module_build=$2;; --firmware-dir) firmware_dir=$2;; esac
      shift 2 ;;
    --apply) apply=true; shift;;
    --check) apply=false; shift;;
    --install-netsurf) install_netsurf=true; shift;;
    --camera-test) camera_test=true; shift;;
    --help) usage; exit 0;;
    *) fail "unknown option: $1";;
  esac
done
((${#targets[@]} > 0 && ${#targets[@]} <= 16)) || fail 'specify between one and sixteen --target destinations'
if [[ $apply == false && ( $install_netsurf == true || $camera_test == true ) ]]; then fail 'package and camera options require --apply'; fi
declare -A seen_targets=() seen_ips=() seen_uids=() seen_names=()
for target in "${targets[@]}"; do
  [[ $target =~ ^ubuntu@[A-Za-z0-9][A-Za-z0-9.-]*$ && $target != *..* && $target != *. ]] || fail "invalid destination: $target"
  [[ ! -v seen_targets[$target] ]] || fail "duplicate destination: $target"
  seen_targets[$target]=1
done
for executable in awk base64 bash cat chmod cp date dirname find grep install mktemp readelf rm sha256sum ssh sshpass stat strings tar timeout wc; do
  command -v "$executable" >/dev/null || fail "missing local executable: $executable"
done
# shellcheck source=scripts/pico-imx7-artifacts.bash
source "$script_dir/pico-imx7-artifacts.bash"
# shellcheck source=scripts/pico-imx7-policy-catalog.bash
source "$script_dir/pico-imx7-policy-catalog.bash"
[[ -d $firmware_dir ]] || fail "firmware directory missing: $firmware_dir; run ./fetch-ap6335-firmware.sh first"
validate_pico_artifacts "$module_build" "$firmware_dir"
selected_night_exposure=false
if LC_ALL=C readelf -p .modinfo -- "$modules_dir/ov5645_camera_mipi_v2.ko" |
  awk '/parm=night_max_exposure_ms:/ {found=1} END {exit !found}'; then
  selected_night_exposure=true
fi
readonly selected_night_exposure
work_dir=$(mktemp -d)
cleanup() { rm -rf -- "$work_dir"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
install -d -- "$work_dir/identity"
"$script_dir/configure-pico-imx7-hostname.sh" --image-root "$work_dir/identity" >/dev/null
# Use the sole generated identity algorithm, without installing it on a board.
{
  printf 'pico_identity() (\n'
  cat "$work_dir/identity/usr/local/sbin/pico-imx7-hostname"
  printf ')\n'
  cat "$script_dir/pico-imx7-artifacts.bash"
} > "$work_dir/prefix"
ssh_run() {
  local destination=$1 seconds=$2; shift 2
  env -i PATH="$PATH" SSH_TECHNEXION_TARGET="$destination" SSH_TECHNEXION_TIMEOUT_SECONDS="$seconds" \
    "$script_dir/ssh-technexion.sh" -4 "$@"
}
make_request() {
  local request=$1 manifest=$2 uid=$3 failures=$4
  cat "$work_dir/prefix" > "$request"
  # Only verified fixed-format UID and hashes are interpolated. Manifest is
  # generated locally from fixed inventories and inserted as literal data.
  printf 'expected_uid=%q\nexpected_dtb=%q\nexpected_record=%q\nselected_night_exposure=%s\n' \
    "$uid" "$(artifact_sha256 "$boot_dtb")" "$(artifact_sha256 "$module_record")" "$selected_night_exposure" >> "$request"
  printf "plan_text=\$(cat <<'PICO_MANIFEST'\n" >> "$request"
  [[ -z $manifest ]] || cat "$manifest" >> "$request"
  printf '\nPICO_MANIFEST\n)\n' >> "$request"
  printf "initial_failures=\$(cat <<'PICO_FAILURES'\n" >> "$request"
  [[ -z $failures ]] || cat "$failures" >> "$request"
  {
    printf '\nPICO_FAILURES\n)\n'
    printf 'camera_test=%s\ninstall_netsurf=%s\n' "$camera_test" "$install_netsurf"
    cat "$script_dir/pico-imx7-target.bash"
  } >> "$request"
}
write_manifest() {
  local stage=$1 manifest=$2 context=$3 index path owner mode group uid gid
  uid=$(awk -F: '$1=="ubuntu" {print $3}' "$context/etc/passwd")
  gid=$(awk -F: '$1=="ubuntu" {print $4}' "$context/etc/passwd")
  [[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]] || fail 'invalid ubuntu context identity'
  : > "$manifest"
  for index in "${!module_names[@]}"; do
    path=/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}
    install -D -m 0644 -- "$modules_dir/${module_names[$index]}" "$stage$path"
    printf 'F\t%s\t644\t0:0\t%s\n' "${module_hashes[$index]}" "$path" >> "$manifest"
  done
  for index in "${!firmware_names[@]}"; do
    path=/lib/firmware/${firmware_destinations[$index]}
    install -D -m 0644 -- "$firmware_dir/${firmware_names[$index]}" "$stage$path"
    printf 'F\t%s\t644\t0:0\t%s\n' "$(artifact_sha256 "$stage$path")" "$path" >> "$manifest"
  done
  for path in "${policy_paths[@]}"; do
    owner=0:0
    [[ $path != /home/ubuntu/* ]] || owner=$uid:$gid
    mode=$(stat -c %a -- "$stage$path")
    printf 'F\t%s\t%s\t%s\t%s\n' "$(artifact_sha256 "$stage$path")" "$mode" "$owner" "$path" >> "$manifest"
  done
  for path in "${hostname_dependencies[@]}"; do
    printf 'L\t../pico-imx7-hostname.service\t-\t-\t/etc/systemd/system/%s/pico-imx7-hostname.service\n' "$path" >> "$manifest"
  done
  for path in "${masked_services[@]}"; do
    printf 'L\t/dev/null\t-\t-\t/etc/systemd/system/%s\n' "$path" >> "$manifest"
  done
  if [[ -L $stage/etc/systemd/system/dnsmasq.service ]]; then printf 'L\t/dev/null\t-\t-\t/etc/systemd/system/dnsmasq.service\n' >> "$manifest"; fi
  for group in audio video render; do
    if awk -F: -v name="$group" '$1==name {found=1} END {exit !found}' "$context/etc/group"; then printf 'G\t-\t-\t-\t%s\n' "$group" >> "$manifest"; fi
  done
}
# Every target is inspected, staged, and checked for unsafe destinations before
# the first persistent write. Original destinations are pinned to their SSH IPv4.
for index in "${!targets[@]}"; do
  target=${targets[$index]}
  directory=$work_dir/$index
  install -d -- "$directory/context" "$directory/root" "$directory/payload/boot"
  make_request "$directory/inspect-request" '' '' ''
  ssh_run "$target" 120 'read -r _ _ peer _ <<< "$SSH_CONNECTION"; sudo -n timeout --signal=TERM --kill-after=10s 110 env PICO_SSH_IP="$peer" bash -s -- --inspect' < "$directory/inspect-request" > "$directory/inspection"
  uid=$(awk -F= '$1=="uid" {print $2}' "$directory/inspection")
  hostname=$(awk -F= '$1=="hostname" {print $2}' "$directory/inspection")
  ip=$(awk -F= '$1=="ip" {print $2}' "$directory/inspection")
  [[ $uid =~ ^[a-f0-9]{16}$ && $hostname =~ ^technexion-[a-f0-9]{1,4}$ && $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail 'malformed target identity response'
  [[ ! -v seen_uids[$uid] ]] || fail "duplicate board UID: $uid"
  [[ ! -v seen_names[$hostname] ]] || fail "short hostname collision: $hostname"
  [[ ! -v seen_ips[$ip] ]] || fail "duplicate resolved IPv4 destination: $ip"
  seen_uids[$uid]=1; seen_names[$hostname]=1; seen_ips[$ip]=1
  ips+=("$ip"); uids+=("$uid"); hostnames+=("$hostname")
  awk '/^failed_units_begin$/ {copy=1;next} /^failed_units_end$/ {copy=0} copy' "$directory/inspection" > "$directory/failures"
  ssh_run "ubuntu@$ip" 90 'read -r _ _ peer _ <<< "$SSH_CONNECTION"; sudo -n timeout --signal=TERM --kill-after=10s 80 env PICO_SSH_IP="$peer" bash -s -- --context' < "$directory/inspect-request" > "$directory/context.tar"
  [[ $(stat -c %s -- "$directory/context.tar") -le 2097152 ]] || fail 'policy context export exceeds 2 MiB'
  tar -C "$directory/context" -xf "$directory/context.tar"
  "$script_dir/configure-pico-imx7-memory.sh" --image-root "$directory/root" > "$directory/staging.log"
  "$script_dir/configure-pico-imx7-hostname.sh" --image-root "$directory/root" >> "$directory/staging.log"
  "$script_dir/configure-pico-imx7-board.sh" --image-root "$directory/root" --context-root "$directory/context" >> "$directory/staging.log"
  write_manifest "$directory/root" "$directory/manifest" "$directory/context"
  make_request "$directory/request" "$directory/manifest" "$uid" "$directory/failures"
  ssh_run "ubuntu@$ip" 120 'read -r _ _ peer _ <<< "$SSH_CONNECTION"; sudo -n timeout --signal=TERM --kill-after=10s 110 env PICO_SSH_IP="$peer" bash -s -- --plan' < "$directory/request" > "$directory/plan"
  printf '\nTarget %s: %s (full UID %s; pinned IPv4 %s)\n' "$target" "$hostname" "$uid" "$ip"
  cat "$directory/inspection" "$directory/plan"
done
if [[ $apply == false ]]; then
  printf '\nInspection complete. Use --apply with the same explicit targets to install the reported recorded set.\n'
  exit 0
fi
# Evidence is bounded by at most 16 boards, fixed inspections, and 64 KiB apt
# diagnostics per invocation. Refuse growth beyond 20 runs instead of deleting
# someone else's evidence automatically.
evidence_parent=$repo_dir/artifacts/target-updates
[[ ! -L $evidence_parent ]] || fail 'unsafe evidence directory'
install -d -- "$evidence_parent"
[[ $(find "$evidence_parent" -mindepth 1 -maxdepth 1 -type d | wc -l) -lt 20 ]] || fail 'target evidence limit reached; remove an old run explicitly'
evidence=$(mktemp -d "$evidence_parent/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")
run_id=$(cat /proc/sys/kernel/random/uuid)
[[ $run_id =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || fail 'cannot generate updater run identity'
printf 'format=pico-imx7-target-update-v1\nrun_id=%s\nmodule_record_sha256=%s\n' "$run_id" "$(artifact_sha256 "$module_record")" > "$evidence/provenance"
for index in "${!targets[@]}"; do
  directory=$work_dir/$index
  ip=${ips[$index]}
  uid=${uids[$index]}
  cp -- "$directory/inspection" "$directory/plan" "$directory/manifest" "$evidence/"
  mv -- "$evidence/inspection" "$evidence/$ip.inspection"
  mv -- "$evidence/plan" "$evidence/$ip.plan"
  mv -- "$evidence/manifest" "$evidence/$ip.manifest"
  printf 'target=%s uid=%s hostname=%s\n' "$ip" "$uid" "${hostnames[$index]}" >> "$evidence/provenance"
  cp -- "$boot_dtb" "$directory/payload/boot/imx7d-pico-pi.dtb"
  mv -- "$directory/root" "$directory/payload/root"
  cp -- "$directory/request" "$directory/payload/remote"
  tar -C "$directory/payload" -cf "$directory/payload.tar" .
  # The SSH shell owns a timeout process group containing extraction and apply.
  # This remote temporary root is removed on success, failure, or timeout.
  remote_launcher=$(cat <<'LAUNCHER'
set -euo pipefail
payload=$(mktemp -d /tmp/pico-imx7-payload.XXXXXX)
trap 'rm -rf -- "$payload"' EXIT
trap 'exit 143' TERM HUP
tar -C "$payload" -xf -
export payload
bash "$payload/remote" --apply
LAUNCHER
)
  printf -v launcher_quoted '%q' "$remote_launcher"
  remote_command="read -r _ _ peer _ <<< \"\$SSH_CONNECTION\"; sudo -n timeout --signal=TERM --kill-after=15s 900 env PICO_SSH_IP=\"\$peer\" bash -c $launcher_quoted"
  if ! ssh_run "ubuntu@$ip" 930 "$remote_command" < "$directory/payload.tar" > "$evidence/$ip.apply" 2>&1; then
    cat "$evidence/$ip.apply" >&2
    fail "apply failed for $ip; bounded evidence: $evidence"
  fi
  cat "$evidence/$ip.apply"
  if grep -Fx 'reboot_needed=true' "$evidence/$ip.apply" >/dev/null; then
    env -i PATH="$PATH" SSH_TECHNEXION_TARGET="ubuntu@$ip" "$script_dir/reboot-technexion.sh"
  else
    printf 'No reboot needed for %s.\n' "$ip"
  fi
  if ! ssh_run "ubuntu@$ip" 180 'read -r _ _ peer _ <<< "$SSH_CONNECTION"; sudo -n timeout --signal=TERM --kill-after=10s 170 env PICO_SSH_IP="$peer" bash -s -- --verify' < "$directory/request" > "$evidence/$ip.verification" 2>&1; then
    cat "$evidence/$ip.verification" >&2
    fail "verification failed for $ip; evidence: $evidence"
  fi
  cat "$evidence/$ip.verification"
done
printf 'Updated and verified %d board(s). Evidence: %s\n' "${#targets[@]}" "$evidence"
