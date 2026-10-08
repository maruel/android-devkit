#!/usr/bin/env bash
# Flash the verified raw image through explicit USB boot assets and UUU.
set -euo pipefail

readonly EXPECTED_DEVICE='imx7d-sdp-15a2:0076'

usage() {
  printf '%s\n' \
    'usage: flash-pico-imx7-emmc.sh --image /absolute/path/to/image.raw --spl /absolute/path/to/imx7-SPL --u-boot /absolute/path/to/imx7-u-boot.img [--uuu /absolute/path/to/uuu] [--flash]' >&2
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
  [[ "$path" == /* && -f "$path" && ! -L "$path" && -s "$path" ]] ||
    fail "$option_name must name an existing absolute, non-symlink regular file"
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

image=''
spl=''
u_boot=''
uuu='uuu'
flash=false
while (($# > 0)); do
  case "$1" in
    --image|--spl|--u-boot|--uuu)
      (($# >= 2)) || usage
      case "$1" in
        --image) image="$2" ;;
        --spl) spl="$2" ;;
        --u-boot) u_boot="$2" ;;
        --uuu) uuu="$2" ;;
      esac
      shift 2
      ;;
    --flash) flash=true; shift ;;
    --help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$image" && -n "$spl" && -n "$u_boot" ]] || usage
require_absolute_regular_file '--image' "$image"
require_absolute_regular_file '--spl' "$spl"
require_absolute_regular_file '--u-boot' "$u_boot"
for required_command in awk grep sha256sum; do
  require_command "$required_command"
done
if ((EUID != 0)); then
  require_command sudo
fi
uuu_path="$(command -v -- "$uuu" || true)"
[[ -n "$uuu_path" && -x "$uuu_path" ]] || fail '--uuu must name an executable on PATH or an executable absolute path'
readonly uuu_path

provenance="$image.provenance"
[[ -f "$provenance" && ! -L "$provenance" ]] ||
  fail 'image provenance record is missing or symlinked'
image_sha="$(sha256_file "$image")"
grep -Fx 'format=pico-imx7-ubuntu-22.04-derived-image-v1' -- "$provenance" >/dev/null ||
  fail 'image provenance record has an unexpected format'
grep -Fx "derived_image_sha256=$image_sha" -- "$provenance" >/dev/null ||
  fail 'image provenance checksum does not match the image'

run_uuu() {
  if ((EUID == 0)); then
    "$uuu_path" "$@"
  else
    sudo -- "$uuu_path" "$@"
  fi
}

discover_device() {
  local discovery matches
  discovery="$(run_uuu -lsusb)" || fail 'UUU USB discovery failed; set the Pico i.MX7 DIP switches to USB boot and reconnect it'
  matches="$(printf '%s\n' "$discovery" | awk '
    function normalize(value) {
      value = tolower(value)
      sub(/^0x/, "", value)
      return value
    }
    $2 == "MX7D" && $3 == "SDP:" && normalize($4) == "15a2" && normalize($5) == "0076" { count++ }
    END { print count + 0 }
  ')"
  [[ "$matches" == 1 ]] ||
    fail "expected exactly one USB-boot Pico i.MX7 ($EXPECTED_DEVICE); found $matches"
}

if ((EUID != 0)); then
  sudo -v
fi
discover_device
if [[ "$flash" != true ]]; then
  printf 'dry run only; eMMC will not be written.\n'
  printf 'image=%s sha256=%s\n' "$image" "$image_sha"
  printf 'spl=%s sha256=%s\n' "$spl" "$(sha256_file "$spl")"
  printf 'u_boot=%s sha256=%s\n' "$u_boot" "$(sha256_file "$u_boot")"
  printf 'USB device=%s\n' "$EXPECTED_DEVICE"
  printf 'resolved UUU command: %s -b emmc_imx7_img %s %s %s\n' "$uuu_path" "$spl" "$u_boot" "$image"
  printf 'to flash, rerun with --flash and approve the prompt\n'
  exit 0
fi
[[ -t 0 && -t 1 ]] || fail '--flash requires an interactive terminal'
printf 'erase and write the verified image to Pico i.MX7 eMMC? [Y/n] '
IFS= read -r confirmation || fail 'could not read flash confirmation'
case "$confirmation" in
  ''|y|Y|yes|YES) ;;
  *)
    printf 'flash cancelled; eMMC was not written.\n'
    exit 0
    ;;
esac
discover_device
printf 'flashing verified image to Pico i.MX7 eMMC using UUU. Do not disconnect power or USB.\n'
run_uuu -b emmc_imx7_img "$spl" "$u_boot" "$image"
printf 'UUU completed; restore the Pico i.MX7 DIP switches to normal eMMC boot before restarting it.\n'
