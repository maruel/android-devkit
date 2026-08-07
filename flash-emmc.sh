#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: flash-emmc.sh [--spl /absolute/path/to/imx7-SPL --u-boot /absolute/path/to/imx7-u-boot.img] [--image-name name.raw] [--uuu /absolute/path/to/uuu] [--flash --confirm-image FLASH_IMAGE_SHA256=... --confirm-device FLASH_DEVICE=imx7d-sdp-15a2:0076]' >&2
  exit 2
}

spl=''
u_boot=''
uuu=''
image_name='pico-imx7-ubuntu-22.04.raw'
declare -a flash_arguments=()
while (($# > 0)); do
  case "$1" in
    --spl) (($# >= 2)) || usage; spl="$2"; shift 2 ;;
    --u-boot) (($# >= 2)) || usage; u_boot="$2"; shift 2 ;;
    --uuu) (($# >= 2)) || usage; uuu="$2"; shift 2 ;;
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

[[ "$image_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.raw$ ]] || {
  printf '%s\n' 'error: --image-name must be a single .raw filename' >&2
  exit 1
}
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
assets_dir="$script_dir/artifacts/uuu-assets/pico-imx7"
[[ -n "$spl" ]] || spl="$assets_dir/imx7-SPL"
[[ -n "$u_boot" ]] || u_boot="$assets_dir/imx7-u-boot.img"
[[ -n "$uuu" ]] || uuu="$assets_dir/uuu"
exec "$script_dir/scripts/flash-pico-imx7-emmc.sh" \
  --image "$script_dir/artifacts/ubuntu-22.04/$image_name" \
  --spl "$spl" \
  --u-boot "$u_boot" \
  --uuu "$uuu" \
  "${flash_arguments[@]}"
