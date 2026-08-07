#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'usage: flash-pico-imx7-ubuntu-image.sh --image /absolute/path/to/image.raw --device /dev/sdX [--flash' \
    '  --confirm-image FLASH_IMAGE_SHA256=... --confirm-device FLASH_DEVICE=/dev/sdX]' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

image=""
device=""
flash=false
confirm_image=""
confirm_device=""
while (($# > 0)); do
  case "$1" in
    --image|--device|--confirm-image|--confirm-device)
      (($# >= 2)) || usage
      case "$1" in
        --image) image="$2" ;;
        --device) device="$2" ;;
        --confirm-image) confirm_image="$2" ;;
        --confirm-device) confirm_device="$2" ;;
      esac
      shift 2
      ;;
    --flash) flash=true; shift ;;
    --help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$image" && -n "$device" ]] || usage
[[ "$image" == /* && -f "$image" && ! -L "$image" && -s "$image" ]] ||
  fail '--image must name an existing absolute, non-symlink regular file'
[[ "$device" =~ ^/dev/(mmcblk[0-9]+|nvme[0-9]+n[0-9]+|sd[a-z]+)$ ]] ||
  fail '--device must be a whole SD, NVMe, or SCSI disk (not a partition)'
[[ -b "$device" ]] || fail '--device must name an existing block device'
for required_command in awk blockdev dd findmnt grep lsblk sha256sum sync wc; do
  require_command "$required_command"
done

device_type="$(lsblk --noheadings --output TYPE -- "$device" | awk 'NF { print; exit }')"
[[ "$device_type" == disk ]] || fail '--device must be a whole disk'
mounted_paths="$(lsblk --noheadings --output MOUNTPOINT -- "$device" | awk 'NF { print }')"
[[ -z "$mounted_paths" ]] || fail "refusing to flash a disk with mounted paths: $mounted_paths"
root_source="$(findmnt --noheadings --output SOURCE / 2>/dev/null || true)"
[[ "$root_source" != "$device" && "$root_source" != "$device"[0-9]* && "$root_source" != "$device"p[0-9]* ]] ||
  fail 'refusing to flash the current root filesystem device'
image_bytes="$(wc -c < "$image")"
device_bytes="$(blockdev --getsize64 "$device")"
((image_bytes <= device_bytes)) || fail 'image is larger than the selected device'
image_sha="$(sha256_file "$image")"
provenance="$image.provenance"
[[ -f "$provenance" && ! -L "$provenance" ]] ||
  fail 'image provenance record is missing or symlinked'
grep -Fx 'format=pico-imx7-ubuntu-22.04-derived-image-v1' -- "$provenance" >/dev/null ||
  fail 'image provenance record has an unexpected format'
grep -Fx "derived_image_sha256=$image_sha" -- "$provenance" >/dev/null ||
  fail 'image provenance checksum does not match the image'

required_image_confirmation="FLASH_IMAGE_SHA256=$image_sha"
required_device_confirmation="FLASH_DEVICE=$device"
if [[ "$flash" != true ]]; then
  printf 'dry run only; no device will be written.\n'
  printf 'image=%s sha256=%s bytes=%s\n' "$image" "$image_sha" "$image_bytes"
  printf 'device=%s bytes=%s\n' "$device" "$device_bytes"
  printf 'to flash, add --flash --confirm-image %s --confirm-device %s\n' \
    "$required_image_confirmation" "$required_device_confirmation"
  exit 0
fi
[[ "$confirm_image" == "$required_image_confirmation" ]] ||
  fail 'image confirmation does not match the verified image'
[[ "$confirm_device" == "$required_device_confirmation" ]] ||
  fail 'device confirmation does not match the selected device'
mounted_paths="$(lsblk --noheadings --output MOUNTPOINT -- "$device" | awk 'NF { print }')"
[[ -z "$mounted_paths" ]] || fail "device acquired mounted paths before flashing: $mounted_paths"
if ((EUID == 0)); then
  dd if="$image" of="$device" bs=4M conv=fsync status=progress
else
  require_command sudo
  sudo dd if="$image" of="$device" bs=4M conv=fsync status=progress
fi
sync
printf 'flashed verified Pico i.MX7 Ubuntu image to %s\n' "$device"
