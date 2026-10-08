#!/usr/bin/env bash
# Fetch and verify the pinned TechNexion Ubuntu raw image.
set -euo pipefail

readonly IMAGE_URL='https://download.technexion.com/images/pico-imx7/pi-lcd800x480/ubuntu-22.04.xz'
readonly COMPRESSED_SHA256='d23c04fe49b2537e5240f4b448f4d43f720d80ebb057d0bb62238a13b1a5b3ef'
readonly RAW_SHA256='9fb5d12f5f50167d5529979b86fad7fcba454ea5b8e984feb43f2446c0e6f3ed'

usage() {
  printf '%s\n' 'usage: fetch-base-image.sh' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

if (($# != 0)); then
  usage
fi
for required_command in curl dirname mkdir mktemp mv rm sha256sum xz; do
  command -v -- "$required_command" >/dev/null 2>&1 ||
    fail "required executable not found: $required_command"
done
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
artifacts_dir="$script_dir/artifacts"
compressed_image="$artifacts_dir/ubuntu-22.04.xz"
raw_dir="$artifacts_dir/ubuntu-22.04"
raw_image="$raw_dir/ubuntu-22.04.raw"
if [[ -e "$raw_image" || -L "$raw_image" ]]; then
  [[ -f "$raw_image" && ! -L "$raw_image" && -s "$raw_image" ]] ||
    fail "raw image path is unsafe: $raw_image"
  [[ "$(sha256_file "$raw_image")" == "$RAW_SHA256" ]] ||
    fail "existing raw image checksum is wrong: $raw_image"
  printf 'verified existing base image: %s\n' "$raw_image"
  exit 0
fi
mkdir -p -- "$artifacts_dir" "$raw_dir"
if [[ ! -e "$compressed_image" && ! -L "$compressed_image" ]]; then
  temporary_download="$(mktemp "$artifacts_dir/.ubuntu-22.04.XXXXXX")"
  readonly temporary_download
  cleanup() { rm -f -- "$temporary_download"; }
  trap cleanup EXIT
  curl --fail --location --proto '=https' --output "$temporary_download" -- "$IMAGE_URL"
  [[ "$(sha256_file "$temporary_download")" == "$COMPRESSED_SHA256" ]] ||
    fail 'downloaded compressed image checksum is wrong'
  mv -T -- "$temporary_download" "$compressed_image"
  trap - EXIT
fi
[[ -f "$compressed_image" && ! -L "$compressed_image" && -s "$compressed_image" ]] ||
  fail "compressed image path is unsafe: $compressed_image"
[[ "$(sha256_file "$compressed_image")" == "$COMPRESSED_SHA256" ]] ||
  fail "compressed image checksum is wrong: $compressed_image"
temporary_raw="$(mktemp "$raw_dir/.ubuntu-22.04.raw.XXXXXX")"
readonly temporary_raw
cleanup_raw() { rm -f -- "$temporary_raw"; }
trap cleanup_raw EXIT
xz --decompress --stdout -- "$compressed_image" > "$temporary_raw"
[[ "$(sha256_file "$temporary_raw")" == "$RAW_SHA256" ]] ||
  fail 'decompressed raw image checksum is wrong'
mv -T -- "$temporary_raw" "$raw_image"
trap - EXIT
printf 'downloaded and verified base image: %s\n' "$raw_image"
