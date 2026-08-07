#!/usr/bin/env bash
set -euo pipefail

readonly BASE_IMAGE_SHA256='9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed'
readonly KERNEL_COMMIT='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
readonly PREPARED_CONFIG_SHA256='614e375075b3abd70dbf3461e12d878531d81a713899ff5923dca416465d445c'
readonly TARGET_RELEASE='5.15.71'
readonly TARGET_VERMAGIC='5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8 '

usage() {
  printf '%s\n' 'usage: create-pico-imx7-ubuntu-image.sh --base-image /absolute/path/to/ubuntu-22.04.raw --module-build /absolute/path/to/validated-module-build --output-image /absolute/path/to/new-image.raw' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
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
while (($# > 0)); do
  case "$1" in
    --base-image|--module-build|--output-image)
      (($# >= 2)) || usage
      case "$1" in
        --base-image) base_image="$2" ;;
        --module-build) module_build="$2" ;;
        --output-image) output_image="$2" ;;
      esac
      shift 2
      ;;
    --help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$base_image" && -n "$module_build" && -n "$output_image" ]] || usage
require_absolute_regular_file '--base-image' "$base_image"
[[ "$module_build" == /* && -d "$module_build" && ! -L "$module_build" ]] ||
  fail '--module-build must name an existing absolute, non-symlink directory'
[[ "$output_image" == /* ]] || fail '--output-image must be an absolute path'
[[ ! -e "$output_image" && ! -L "$output_image" && ! -e "$output_image.provenance" && ! -L "$output_image.provenance" ]] ||
  fail 'refusing to overwrite an existing image or provenance record'

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
  'ath10k_pci.ko'
  'mxc_v4l2_capture.ko'
  'v4l2-int-device.ko'
  'mxc_mipi_csi.ko'
  'ov5640_camera_mipi_v2.ko'
)
declare -a module_destinations=(
  'kernel/drivers/net/wireless/ath/ath.ko'
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_core.ko'
  'kernel/drivers/net/wireless/ath/ath10k/ath10k_pci.ko'
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

# Ubuntu may make host kernels unreadable to regular users. libguestfs needs
# one only for its private appliance, so restrict elevation to guestfish and
# the handoff of its temporary archive.
sudo -v
user_owner="$(id -u):$(id -g)"
readonly user_owner
guestfish_as_root() {
  sudo -- guestfish "$@"
}
restore_user_ownership() {
  sudo -- chown -- "$user_owner" "$1"
}

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
mkdir -- "$stage_root"
cp --reflink=auto --preserve=mode,timestamps -- "$base_image" "$working_image"
guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : tar-out /lib/modules "$archive"
restore_user_ownership "$archive"
mkdir -p -- "$stage_root/lib/modules"
tar -C "$stage_root/lib/modules" -xf "$archive"
for index in "${!module_names[@]}"; do
  destination="$stage_root/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}"
  [[ -f "$destination" && ! -L "$destination" ]] ||
    fail "base image does not contain expected module path: ${module_destinations[$index]}"
  cp --preserve=mode -- "$modules_dir/${module_names[$index]}" "$destination"
done
"$depmod_command" -b "$stage_root" "$TARGET_RELEASE"
tar -C "$stage_root/lib/modules" -cf "$archive" .
guestfish_as_root --rw -a "$working_image" run : mount /dev/sda2 / : tar-in "$archive" /lib/modules
for index in "${!module_names[@]}"; do
  image_module_sha="$(guestfish_as_root --ro -a "$working_image" run : mount-ro /dev/sda2 / : checksum sha256 "/lib/modules/$TARGET_RELEASE/${module_destinations[$index]}")"
  [[ "$image_module_sha" == "$(sha256_file "$modules_dir/${module_names[$index]}")" ]] ||
    fail "image verification failed for ${module_names[$index]}"
done
image_sha="$(sha256_file "$working_image")"
mv -T -- "$working_image" "$output_image"
printf '%s\n' \
  'format=pico-imx7-ubuntu-22.04-derived-image-v1' \
  "base_image_sha256=$BASE_IMAGE_SHA256" \
  "module_build_record_sha256=$(sha256_file "$module_record")" \
  "kernelrelease=$TARGET_RELEASE" \
  "derived_image_sha256=$image_sha" > "$output_image.provenance"
printf 'created verified Pico i.MX7 Ubuntu flash image: %s\n' "$output_image"
