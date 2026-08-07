#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: flash-sd-card.sh --device /dev/sdX [--image-name name.raw] [--flash --confirm-image FLASH_IMAGE_SHA256=... --confirm-device FLASH_DEVICE=/dev/sdX]' >&2
  exit 2
}

device=""
image_name='pico-imx7-ubuntu-22.04.raw'
declare -a flash_arguments=()
while (($# > 0)); do
  case "$1" in
    --device) (($# >= 2)) || usage; device="$2"; shift 2 ;;
    --image-name) (($# >= 2)) || usage; image_name="$2"; shift 2 ;;
    --flash) flash_arguments+=(--flash); shift ;;
    --confirm-image|--confirm-device)
      (($# >= 2)) || usage
      flash_arguments+=("$1" "$2")
      shift 2
      ;;
    --help) usage ;;
    *) usage ;;
  esac
done
[[ -n "$device" ]] || usage
[[ "$image_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.raw$ ]] ||
  { printf '%s\n' 'error: --image-name must be a single .raw filename' >&2; exit 1; }
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
exec "$script_dir/scripts/flash-pico-imx7-ubuntu-image.sh" \
  --image "$script_dir/artifacts/ubuntu-22.04/$image_name" \
  --device "$device" \
  "${flash_arguments[@]}"
