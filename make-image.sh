#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'usage: make-image.sh [--rebuilt] [--output-name name.raw]' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

rebuilt=false
output_name='pico-imx7-ubuntu-22.04.raw'
while (($# > 0)); do
  case "$1" in
    --rebuilt) rebuilt=true; shift ;;
    --output-name) (($# >= 2)) || usage; output_name="$2"; shift 2 ;;
    --help) usage ;;
    *) usage ;;
  esac
done
[[ "$output_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.raw$ ]] ||
  fail '--output-name must be a single .raw filename'
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
command -v guestfish >/dev/null 2>&1 ||
  fail 'install image prerequisites first: sudo apt install --no-install-recommends kmod libguestfs-tools'
base_image="$script_dir/artifacts/ubuntu-22.04/ubuntu-22.04.raw"
firmware_dir="$script_dir/artifacts/firmware/qca9377"
module_build="$script_dir/prebuilt/pico-imx7/ubuntu-22.04-5.15.71"
if [[ "$rebuilt" == true ]]; then
  module_build="$script_dir/artifacts/module-build"
fi
[[ -f "$base_image" && ! -L "$base_image" && -s "$base_image" ]] ||
  fail "base image is missing: $base_image; run ./fetch-base-image.sh first"
"$script_dir/fetch-qca9377-firmware.sh"
exec "$script_dir/scripts/create-pico-imx7-ubuntu-image.sh" \
  --base-image "$base_image" \
  --module-build "$module_build" \
  --firmware-dir "$firmware_dir" \
  --output-image "$script_dir/artifacts/ubuntu-22.04/$output_name"
