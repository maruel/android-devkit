#!/usr/bin/env bash
set -euo pipefail

readonly BASE_IMAGE_SHA256='9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed'
readonly KERNEL_COMMIT='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
readonly PREPARED_CONFIG_SHA256='644090a71b5dbc975720d6e4fbdb391b9e8869064ac6fd6689a64c12965093dc'
readonly TARGET_RELEASE='5.15.71'
readonly TARGET_VERMAGIC='5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8 '
readonly QCA9377_BOARD_SHA256='127d35d82edb46278f30c448cbca664d755ff0d5fed57b649959cdbc4208c768'
readonly QCA9377_BOARD_2_SHA256='0fdcc7838f478da81704de88f7b33e28862110c6d5decf7818543f8e37e6cd98'
readonly QCA9377_FIRMWARE_SDIO_5_SHA256='017b4ae7bdb5821ecb439fbf96d198421a57926918f2513db5fbd6d9c01debe6'

usage() {
  printf '%s\n' 'usage: create-pico-imx7-ubuntu-image.sh --base-image /absolute/path/to/ubuntu-22.04.raw --module-build /absolute/path/to/validated-module-build --firmware-dir /absolute/path/to/qca9377-firmware --output-image /absolute/path/to/new-image.raw' >&2
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

module_vermagic() {
  local module="$1" values count
  values="$(LC_ALL=C strings -a -- "$module" | awk -F= '$1 == "vermagic" { print substr($0, 10) }')"
  count="$(printf '%s\n' "$values" | sed '/^$/d' | wc -l)"
  [[ "$count" == 1 ]] || fail "module must contain exactly one vermagic value: $module"
  printf '%s\n' "$values"
}

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

for required_command in awk chown cp dirname guestfish grep id mkdir mktemp mv readelf sed sha256sum strings sudo tar wc; do
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
for required_line in \
  'format=pico-imx7-ubuntu-22.04-module-build-v1' \
  "kernel_commit=$KERNEL_COMMIT" \
  "prepared_config_sha256=$PREPARED_CONFIG_SHA256" \
  "kernelrelease=$TARGET_RELEASE" \
  "expected_vermagic=$TARGET_VERMAGIC"; do
  grep -Fx -- "$required_line" "$module_record" >/dev/null ||
    fail "module record is missing required identity: $required_line"
done

declare -a module_names=(
  'ath.ko'
  'ath10k_core.ko'
  'ath10k_sdio.ko'
  'mxc_v4l2_capture.ko'
  'v4l2-int-device.ko'
  'mxc_mipi_csi.ko'
  'ov5640_camera_mipi_v2.ko'
)
declare -a module_destinations=(
  'kernel/drivers/net/wireless/ath/ath.ko'
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko'
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_sdio.ko'
  'kernel/drivers/media/platform/mxc/capture/mxc_v4l2_capture.ko'
  'kernel/drivers/media/platform/mxc/capture/v4l2-int-device.ko'
  'kernel/drivers/media/platform/mxc/capture/mxc_mipi_csi.ko'
  'kernel/drivers/media/platform/mxc/capture/ov5640_camera_mipi_v2.ko'
)
for module_name in "${module_names[@]}"; do
  module="$modules_dir/$module_name"
  require_absolute_regular_file "module $module_name" "$module"
  readelf -h -- "$module" | grep -Eq 'Machine:.*ARM' || fail "module is not an ARM ELF object: $module_name"
  [[ "$(module_vermagic "$module")" == "$TARGET_VERMAGIC" ]] ||
    fail "module vermagic does not match the target image: $module_name"
done
declare -a firmware_names=(
  'board.bin'
  'board-2.bin'
  'firmware-sdio-5.bin'
)
declare -a firmware_destinations=(
  'ath10k/QCA9377/hw1.0/board.bin'
  'ath10k/QCA9377/hw1.0/board-2.bin'
  'ath10k/QCA9377/hw1.0/firmware-sdio-5.bin'
)
require_absolute_regular_file '--firmware-dir/board.bin' "$firmware_dir/board.bin"
require_absolute_regular_file '--firmware-dir/board-2.bin' "$firmware_dir/board-2.bin"
require_absolute_regular_file '--firmware-dir/firmware-sdio-5.bin' "$firmware_dir/firmware-sdio-5.bin"
[[ "$(sha256_file "$firmware_dir/board.bin")" == "$QCA9377_BOARD_SHA256" ]] ||
  fail 'QCA9377 fallback board firmware checksum does not match the pinned upstream file'
[[ "$(sha256_file "$firmware_dir/board-2.bin")" == "$QCA9377_BOARD_2_SHA256" ]] ||
  fail 'QCA9377 board-2 firmware checksum does not match the pinned upstream file'
[[ "$(sha256_file "$firmware_dir/firmware-sdio-5.bin")" == "$QCA9377_FIRMWARE_SDIO_5_SHA256" ]] ||
  fail 'QCA9377 SDIO firmware checksum does not match the pinned upstream file'

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
archive="$temporary/modules.tar"
firmware_archive="$temporary/firmware.tar"
mkdir -- "$stage_root"
cp --reflink=auto --preserve=mode,timestamps -- "$base_image" "$working_image"
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /lib/modules "$archive"
restore_user_ownership "$archive"
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /lib/firmware "$firmware_archive"
restore_user_ownership "$firmware_archive"
mkdir -p -- "$stage_root/lib/modules"
tar -C "$stage_root/lib/modules" -xf "$archive"
mkdir -p -- "$stage_root/lib/firmware"
tar -C "$stage_root/lib/firmware" -xf "$firmware_archive"
for index in "${!module_names[@]}"; do
  destination="$stage_root/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}"
  destination_parent="$(dirname -- "$destination")"
  [[ -d "$destination_parent" && ! -L "$destination_parent" ]] ||
    fail "base image does not contain expected module directory: ${module_destinations[$index]}"
  cp --preserve=mode -- "$modules_dir/${module_names[$index]}" "$destination"
done
for index in "${!firmware_names[@]}"; do
  destination="$stage_root/lib/firmware/${firmware_destinations[$index]}"
  mkdir -p -- "$(dirname -- "$destination")"
  cp --preserve=mode -- "$firmware_dir/${firmware_names[$index]}" "$destination"
done
"$depmod_command" -b "$stage_root" "$TARGET_RELEASE"
tar -C "$stage_root/lib/modules" -cf "$archive" .
tar -C "$stage_root/lib/firmware" -cf "$firmware_archive" .
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$archive" /lib/modules
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$firmware_archive" /lib/firmware
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
image_sha="$(sha256_file "$working_image")"
mv -T -- "$working_image" "$output_image"
printf '%s\n' \
  'format=pico-imx7-ubuntu-22.04-derived-image-v1' \
  "base_image_sha256=$BASE_IMAGE_SHA256" \
  "module_build_record_sha256=$(sha256_file "$module_record")" \
  "qca9377_board_sha256=$QCA9377_BOARD_SHA256" \
  "qca9377_board_2_sha256=$QCA9377_BOARD_2_SHA256" \
  "qca9377_firmware_sdio_5_sha256=$QCA9377_FIRMWARE_SDIO_5_SHA256" \
  "kernelrelease=$TARGET_RELEASE" \
  "derived_image_sha256=$image_sha" > "$output_image.provenance"
printf 'created verified Pico i.MX7 Ubuntu flash image: %s\n' "$output_image"
