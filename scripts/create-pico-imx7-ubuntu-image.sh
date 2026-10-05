#!/usr/bin/env bash
set -euo pipefail

readonly BASE_IMAGE_SHA256='9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed'

usage() {
  printf '%s\n' 'usage: create-pico-imx7-ubuntu-image.sh --base-image /absolute/path/to/ubuntu-22.04.raw --module-build /absolute/path/to/validated-module-build --firmware-dir /absolute/path/to/ap6335-firmware --output-image /absolute/path/to/new-image.raw' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

refuse_existing_output() {
  local candidate
  printf '%s\n' 'error: refusing to overwrite an existing image or provenance record' >&2
  printf '%s\n' 'To rebuild, delete only the existing derived output(s):' >&2
  for candidate in "$output_image" "$output_image.provenance"; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      printf '  rm -f -- %q\n' "$candidate" >&2
    fi
  done
  exit 1
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

require_absolute_regular_file() {
  local option_name="$1" path="$2"
  [[ "$path" == /* ]] || fail "$option_name must be an absolute path"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] ||
    fail "$option_name must name a non-empty, non-symlink regular file"
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=scripts/pico-imx7-artifacts.bash
source "$script_dir/pico-imx7-artifacts.bash"
memory_policy_script="$script_dir/configure-pico-imx7-memory.sh"
hostname_policy_script="$script_dir/configure-pico-imx7-hostname.sh"
readonly memory_policy_script hostname_policy_script

base_image=""
module_build=""
output_image=""
firmware_dir=""
while (($# > 0)); do
  case "$1" in
    --base-image|--module-build|--firmware-dir|--output-image)
      (($# >= 2)) || usage
      case "$1" in
        --base-image) base_image="$2" ;;
        --module-build) module_build="$2" ;;
        --firmware-dir) firmware_dir="$2" ;;
        --output-image) output_image="$2" ;;
      esac
      shift 2
      ;;
    --help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$base_image" && -n "$module_build" && -n "$firmware_dir" && -n "$output_image" ]] || usage
require_absolute_regular_file '--base-image' "$base_image"
[[ "$module_build" == /* && -d "$module_build" && ! -L "$module_build" ]] ||
  fail '--module-build must name an existing absolute, non-symlink directory'
[[ "$firmware_dir" == /* && -d "$firmware_dir" && ! -L "$firmware_dir" ]] ||
  fail '--firmware-dir must name an existing absolute, non-symlink directory'
[[ "$output_image" == /* ]] || fail '--output-image must be an absolute path'
if [[ -e "$output_image" || -L "$output_image" || -e "$output_image.provenance" || -L "$output_image.provenance" ]]; then
  refuse_existing_output
fi

for required_command in awk chown cp dirname guestfish grep id mkdir mktemp mv readelf rm sed sha256sum strings sudo tar wc; do
  require_command "$required_command"
done
depmod_command="$(command -v depmod || true)"
if [[ -z "$depmod_command" ]]; then
  for candidate in /usr/sbin/depmod /sbin/depmod; do
    if [[ -x "$candidate" ]]; then
      depmod_command="$candidate"
      break
    fi
  done
fi
[[ -n "$depmod_command" ]] || fail 'required executable not found: depmod'
readonly depmod_command

[[ "$(sha256_file "$base_image")" == "$BASE_IMAGE_SHA256" ]] ||
  fail 'base image SHA-256 does not match the inspected Ubuntu 22.04 image'
module_record="$module_build/modules.record"
modules_dir="$module_build/modules"
require_absolute_regular_file '--module-build/modules.record' "$module_record"
[[ -d "$modules_dir" && ! -L "$modules_dir" ]] || fail 'validated module directory is missing or symlinked'
boot_dtb="$module_build/boot/imx7d-pico-pi.dtb"
require_absolute_regular_file '--module-build/boot/imx7d-pico-pi.dtb' "$boot_dtb"
require_absolute_regular_file 'memory policy installer' "$memory_policy_script"
[[ -x "$memory_policy_script" ]] || fail 'memory policy installer is not executable'
require_absolute_regular_file 'hostname policy installer' "$hostname_policy_script"
[[ -x "$hostname_policy_script" ]] || fail 'hostname policy installer is not executable'
require_absolute_regular_file 'board policy installer' "$script_dir/configure-pico-imx7-board.sh"
[[ -x "$script_dir/configure-pico-imx7-board.sh" ]] || fail 'board policy installer is not executable'
require_absolute_regular_file 'policy catalog' "$script_dir/pico-imx7-policy-catalog.bash"
validate_pico_artifacts "$module_build" "$firmware_dir"

# shellcheck source=scripts/pico-imx7-policy-catalog.bash
source "$script_dir/pico-imx7-policy-catalog.bash"

# Prefer an unprivileged libguestfs appliance. Some Ubuntu hosts make their
# kernel unreadable to regular users, in which case retry the failed guestfish
# operation with the smallest necessary elevation.
user_owner="$(id -u):$(id -g)"
readonly user_owner
guestfish_uses_sudo=false
guestfish_as_root() {
  if [[ "$guestfish_uses_sudo" == false ]] && guestfish "$@"; then
    return 0
  fi
  if [[ "$guestfish_uses_sudo" == false ]]; then
    printf '%s\n' 'unprivileged guestfish failed; retrying with sudo' >&2
    sudo -v
    guestfish_uses_sudo=true
  fi
  sudo -- guestfish "$@"
}
restore_user_ownership() {
  if [[ "$guestfish_uses_sudo" == true ]]; then
    sudo -- chown -- "$user_owner" "$1"
  fi
}

if ! guestfish --ro -a "$base_image" run : list-filesystems >/dev/null 2>&1; then
  printf '%s\n' 'unprivileged guestfish failed; retrying with sudo' >&2
  sudo -v
  guestfish_uses_sudo=true
fi
layout="$(guestfish_as_root --ro -a "$base_image" run : list-filesystems)"
[[ "$layout" == $'/dev/sda1: vfat\n/dev/sda2: ext4' ]] ||
  fail 'base image partition layout is not the inspected vfat/ext4 layout'
output_parent="$(dirname -- "$output_image")"
readonly output_parent
[[ -d "$output_parent" && ! -L "$output_parent" ]] ||
  fail '--output-image parent must be an existing, non-symlink directory'
temporary="$(mktemp -d "${output_parent}/.pico-imx7-image.XXXXXX")"
readonly temporary
cleanup() {
  [[ ! -e "$temporary" && ! -L "$temporary" ]] || rm -rf -- "$temporary"
}
trap cleanup EXIT
working_image="$temporary/image.raw"
stage_root="$temporary/root"
policy_root="$temporary/policy"
context_root="$temporary/context"
context_archive="$temporary/context.tar"
archive="$temporary/modules.tar"
firmware_archive="$temporary/firmware.tar"
policy_archive="$temporary/policy.tar"
uenv="$temporary/uEnv.txt"
updated_uenv="$temporary/uEnv.txt.updated"
mkdir -- "$stage_root" "$policy_root" "$context_root"
cp --reflink=auto --preserve=mode,timestamps -- "$base_image" "$working_image"
# Read service/config/account context from the disposable derived image only.
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /etc "$context_archive"
restore_user_ownership "$context_archive"
mkdir -- "$context_root/etc"
tar -C "$context_root/etc" -xf "$context_archive"
unit=systemd-resolved.service
if [[ "$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : is-file "/lib/systemd/system/$unit")" == true ]]; then
  mkdir -p -- "$context_root/lib/systemd/system"
  guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : download "/lib/systemd/system/$unit" "$context_root/lib/systemd/system/$unit"
  restore_user_ownership "$context_root/lib/systemd/system/$unit"
fi
ubuntu_uid="$(awk -F: '$1=="ubuntu" {print $3}' "$context_root/etc/passwd")"
ubuntu_gid="$(awk -F: '$1=="ubuntu" {print $4}' "$context_root/etc/passwd")"
[[ "$ubuntu_uid" =~ ^[0-9]+$ && "$ubuntu_gid" =~ ^[0-9]+$ ]] || fail 'invalid image ubuntu account'
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /lib/modules "$archive"
restore_user_ownership "$archive"
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /lib/firmware "$firmware_archive"
restore_user_ownership "$firmware_archive"
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda1 / : download /uEnv.txt "$uenv"
restore_user_ownership "$uenv"
grep -Fx 'wifi_module=qca' "$uenv" >/dev/null ||
  fail 'base image boot configuration does not select the expected QCA device tree'
sed 's/^wifi_module=qca$/wifi_module=brcm/' "$uenv" > "$updated_uenv"
grep -Fx 'wifi_module=brcm' "$updated_uenv" >/dev/null ||
  fail 'failed to select the Broadcom device tree in uEnv.txt'
mkdir -p -- "$stage_root/lib/modules"
tar -C "$stage_root/lib/modules" -xf "$archive"
mkdir -p -- "$stage_root/lib/firmware"
tar -C "$stage_root/lib/firmware" -xf "$firmware_archive"
for index in "${!module_names[@]}"; do
  destination="$stage_root/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}"
  destination_parent="$(dirname -- "$destination")"
  mkdir -p -- "$destination_parent"
  [[ -d "$destination_parent" && ! -L "$destination_parent" ]] ||
    fail "module destination directory is unsafe: ${module_destinations[$index]}"
  cp --preserve=mode -- "$modules_dir/${module_names[$index]}" "$destination"
done
for obsolete_module in \
  'kernel/drivers/net/wireless/ath/ath.ko' \
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko' \
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_sdio.ko' \
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_pci.ko'; do
  rm -f -- "$stage_root/lib/modules/$TARGET_RELEASE/$obsolete_module"
done
for index in "${!firmware_names[@]}"; do
  destination="$stage_root/lib/firmware/${firmware_destinations[$index]}"
  mkdir -p -- "$(dirname -- "$destination")"
  cp --preserve=mode -- "$firmware_dir/${firmware_names[$index]}" "$destination"
done
"$memory_policy_script" --image-root "$policy_root"
"$hostname_policy_script" --image-root "$policy_root"
"$script_dir/configure-pico-imx7-board.sh" --image-root "$policy_root" --context-root "$context_root"
policy_paths+=(/etc/group)
policy_names+=(board_policy_groups)
if [[ -L "$policy_root/etc/systemd/system/dnsmasq.service" ]]; then
  masked_services+=(dnsmasq.service)
fi
"$depmod_command" -b "$stage_root" "$TARGET_RELEASE"
tar -C "$stage_root/lib/modules" -cf "$archive" .
tar -C "$stage_root/lib/firmware" -cf "$firmware_archive" .
# Host staging runs as the developer; privileged policy directories must be root-owned.
tar --owner=0 --group=0 -C "$policy_root" -cf "$policy_archive" .
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$archive" /lib/modules
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$firmware_archive" /lib/firmware
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$policy_archive" /
for policy_path in "${policy_paths[@]}"; do
  owner=0
  group=0
  if [[ "$policy_path" == /home/ubuntu/* ]]; then owner="$ubuntu_uid"; group="$ubuntu_gid"; fi
  guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : chown "$owner" "$group" "$policy_path"
done
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / \
  : chown "$ubuntu_uid" "$ubuntu_gid" /home/ubuntu \
  : chown "$ubuntu_uid" "$ubuntu_gid" /home/ubuntu/.config \
  : chown "$ubuntu_uid" "$ubuntu_gid" /home/ubuntu/.config/autostart
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda1 / : upload "$boot_dtb" /imx7d-pico-pi.dtb : upload "$updated_uenv" /uEnv.txt
for index in "${!module_names[@]}"; do
  image_module_sha="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : checksum sha256 "/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}")"
  [[ "$image_module_sha" == "$(sha256_file "$modules_dir/${module_names[$index]}")" ]] ||
    fail "image verification failed for ${module_names[$index]}"
done
for index in "${!firmware_names[@]}"; do
  image_firmware_sha="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : checksum sha256 "/lib/firmware/${firmware_destinations[$index]}")"
  [[ "$image_firmware_sha" == "$(sha256_file "$firmware_dir/${firmware_names[$index]}")" ]] ||
    fail "image verification failed for ${firmware_names[$index]}"
done
for index in "${!policy_paths[@]}"; do
  policy_path="${policy_paths[$index]}"
  image_policy_sha="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : checksum sha256 "$policy_path")"
  [[ "$image_policy_sha" == "$(sha256_file "$policy_root$policy_path")" ]] ||
    fail "image verification failed for policy ${policy_names[$index]}"
  policy_stat="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : statns "$policy_path")"
  expected_uid=0
  expected_gid=0
  if [[ "$policy_path" == /home/ubuntu/* ]]; then expected_uid="$ubuntu_uid"; expected_gid="$ubuntu_gid"; fi
  [[ "$(printf '%s\n' "$policy_stat" | awk '$1=="st_uid:" {print $2}')" == "$expected_uid" &&
     "$(printf '%s\n' "$policy_stat" | awk '$1=="st_gid:" {print $2}')" == "$expected_gid" ]] ||
    fail "image policy owner verification failed: $policy_path"
  expected_mode=33188 # regular 0644
  [[ ! -x "$policy_root$policy_path" ]] || expected_mode=33261 # regular 0755
  [[ "$(printf '%s\n' "$policy_stat" | awk '$1=="st_mode:" {print $2}')" == "$expected_mode" ]] ||
    fail "image policy mode verification failed: $policy_path"
done
for dependency in "${hostname_dependencies[@]}"; do
  link_path="/etc/systemd/system/$dependency/pico-imx7-hostname.service"
  [[ "$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : is-symlink "$link_path")" == true ]] ||
    fail "hostname policy dependency is missing: $dependency"
  [[ "$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : readlink "$link_path")" == ../pico-imx7-hostname.service ]] ||
    fail "hostname policy dependency is invalid: $dependency"
done
for service in "${masked_services[@]}"; do
  mask_path="/etc/systemd/system/$service"
  [[ "$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : is-symlink "$mask_path")" == true ]] ||
    fail "memory policy mask is missing: $service"
  [[ "$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : readlink "$mask_path")" == /dev/null ]] ||
    fail "memory policy mask is invalid: $service"
done
image_boot_dtb_sha="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda1 / : checksum sha256 /imx7d-pico-pi.dtb)"
[[ "$image_boot_dtb_sha" == "$(sha256_file "$boot_dtb")" ]] ||
  fail 'image verification failed for the Broadcom boot device tree'
image_uenv="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda1 / : cat /uEnv.txt)"
printf '%s\n' "$image_uenv" | grep -Fx 'wifi_module=brcm' >/dev/null ||
  fail 'image verification failed for the Broadcom boot selection'
image_sha="$(sha256_file "$working_image")"
mv -T -- "$working_image" "$output_image"
declare -a provenance_lines=(
  'format=pico-imx7-ubuntu-22.04-derived-image-v1'
  "base_image_sha256=$BASE_IMAGE_SHA256"
  "module_build_record_sha256=$(sha256_file "$module_record")"
  "ap6335_firmware_sha256=$AP6335_FIRMWARE_SHA256"
  "ap6335_nvram_sha256=$AP6335_NVRAM_SHA256"
  "boot_dtb_sha256=$(sha256_file "$boot_dtb")"
  "kernelrelease=$TARGET_RELEASE"
)
for index in "${!policy_paths[@]}"; do
  provenance_lines+=(
    "${policy_names[$index]}_sha256=$(sha256_file "$policy_root${policy_paths[$index]}")"
  )
done
provenance_lines+=("ubuntu_uid=$ubuntu_uid" "ubuntu_gid=$ubuntu_gid")
for service in "${masked_services[@]}"; do provenance_lines+=("service_mask=$service"); done
provenance_lines+=("derived_image_sha256=$image_sha")
printf '%s\n' "${provenance_lines[@]}" > "$output_image.provenance"
printf 'created verified Pico i.MX7 Ubuntu flash image: %s\n' "$output_image"
