#!/usr/bin/env bash
# Extract and verify the authoritative IKCONFIG from the pinned Ubuntu zImage.
set -euo pipefail

# This offset is specific to the documented TechNexion Pico i.MX7 Ubuntu 22.04
# zImage. It is not a general ARM zImage format assumption; see
# docs/workflows/ubuntu.md.
readonly LZOP_OFFSET_BYTES=17384

usage() {
  printf '%s\n' 'usage: extract-pico-imx7-ubuntu-config.sh --zimage /absolute/path/to/zImage --extract-ikconfig /absolute/path/to/scripts/extract-ikconfig --output /absolute/path/to/output.config [--expected-zimage-sha SHA256] [--expected-config-sha SHA256]' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

require_sha256() {
  local value="$1" option_name="$2"
  [[ "$value" =~ ^[a-f0-9]{64}$ ]] || fail "$option_name must be a lowercase 64-character SHA-256"
}

new_output_path() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "refusing to overwrite existing output: $1"
}

zimage=""
extract_ikconfig=""
output=""
expected_zimage_sha=""
expected_config_sha=""

while (($# > 0)); do
  case "$1" in
    --zimage|--extract-ikconfig|--output|--expected-zimage-sha|--expected-config-sha)
      (($# >= 2)) || usage
      case "$1" in
        --zimage) zimage="$2" ;;
        --extract-ikconfig) extract_ikconfig="$2" ;;
        --output) output="$2" ;;
        --expected-zimage-sha) expected_zimage_sha="$2" ;;
        --expected-config-sha) expected_config_sha="$2" ;;
      esac
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$zimage" && -n "$extract_ikconfig" && -n "$output" ]] || usage
[[ "$zimage" == /* ]] || fail '--zimage must be an absolute path'
[[ "$extract_ikconfig" == /* ]] || fail '--extract-ikconfig must be an absolute path'
[[ "$output" == /* ]] || fail '--output must be an absolute path'
[[ -f "$zimage" && ! -L "$zimage" && -s "$zimage" ]] ||
  fail '--zimage must name a non-empty, non-symlink regular file'
[[ -f "$extract_ikconfig" && ! -L "$extract_ikconfig" && -x "$extract_ikconfig" ]] ||
  fail '--extract-ikconfig must name an executable, non-symlink regular file'
if [[ -n "$expected_zimage_sha" ]]; then
  require_sha256 "$expected_zimage_sha" '--expected-zimage-sha'
fi
if [[ -n "$expected_config_sha" ]]; then
  require_sha256 "$expected_config_sha" '--expected-config-sha'
fi

require_command dd
require_command lzop
require_command mktemp
require_command sha256sum
require_command grep
require_command ln
require_command rm
require_command dirname

output_parent="$(dirname -- "$output")"
readonly output_parent
[[ -d "$output_parent" && ! -L "$output_parent" ]] ||
  fail '--output parent must be an existing, non-symlink directory'

provenance_output="${output}.provenance"
new_output_path "$output"
new_output_path "$provenance_output"

zimage_sha="$(sha256sum -- "$zimage")"
zimage_sha="${zimage_sha%% *}"
if [[ -n "$expected_zimage_sha" && "$zimage_sha" != "$expected_zimage_sha" ]]; then
  fail "zImage SHA-256 mismatch: $zimage"
fi

temporary="$(mktemp -d -- "${output_parent}/.pico-imx7-ikconfig.XXXXXX")"
readonly temporary
cleanup() {
  rm -rf -- "$temporary"
}
trap cleanup EXIT

decompressed_kernel="$temporary/decompressed-kernel"
compressed_kernel="$temporary/compressed-kernel"
config_temporary="$temporary/config"
provenance_temporary="$temporary/provenance"

dd if="$zimage" bs=1 skip="$LZOP_OFFSET_BYTES" status=none > "$compressed_kernel"
if lzop --decompress --stdout < "$compressed_kernel" > "$decompressed_kernel"; then
  :
else
  lzop_status=$?
  # The inspected zImage has bytes after its LZOP stream. lzop reports those
  # as exit status 2 after producing valid decompressed output.
  [[ "$lzop_status" == 2 ]] || fail "LZOP extraction failed with status $lzop_status"
fi
[[ -f "$decompressed_kernel" && ! -L "$decompressed_kernel" && -s "$decompressed_kernel" ]] ||
  fail 'LZOP extraction produced no kernel payload'

"$extract_ikconfig" "$decompressed_kernel" > "$config_temporary"
[[ -f "$config_temporary" && ! -L "$config_temporary" && -s "$config_temporary" ]] ||
  fail 'extract-ikconfig produced no configuration'
grep -Fx 'CONFIG_IKCONFIG=y' -- "$config_temporary" >/dev/null ||
  fail 'extracted configuration does not enable CONFIG_IKCONFIG'
grep -Fx 'CONFIG_IKCONFIG_PROC=y' -- "$config_temporary" >/dev/null ||
  fail 'extracted configuration does not enable CONFIG_IKCONFIG_PROC'

config_sha="$(sha256sum -- "$config_temporary")"
config_sha="${config_sha%% *}"
if [[ -n "$expected_config_sha" && "$config_sha" != "$expected_config_sha" ]]; then
  fail 'extracted configuration SHA-256 mismatch'
fi

printf '%s\n' \
  'format=technexion-pico-imx7-ubuntu-22.04-ikconfig-v1' \
  "zimage=$zimage" \
  "zimage_sha256=$zimage_sha" \
  "lzop_offset_bytes=$LZOP_OFFSET_BYTES" \
  "extract_ikconfig=$extract_ikconfig" \
  "config=$output" \
  "config_sha256=$config_sha" > "$provenance_temporary"

# Linking staged files publishes each new pathname atomically and never replaces
# an existing file. Publish provenance first so a published config always has it.
ln -- "$provenance_temporary" "$provenance_output" ||
  fail "refusing to overwrite existing output: $provenance_output"
ln -- "$config_temporary" "$output" ||
  fail "refusing to overwrite existing output: $output"

printf 'extracted Pico i.MX7 Ubuntu 22.04 kernel configuration: %s\n' "$output"
