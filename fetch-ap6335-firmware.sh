#!/usr/bin/env bash
# Fetch checksum-verified AP6335 Wi-Fi firmware and NVRAM.
set -euo pipefail

readonly FIRMWARE_COMMIT='d83b663cdebb0151533950b938d09c5ed5c7d2e3'
readonly FIRMWARE_URL_BASE="https://raw.githubusercontent.com/rcn-ee/sdk-firmware/$FIRMWARE_COMMIT/technexion/Broadcom/AP6335_4.2/Wi-Fi"
readonly FIRMWARE_SHA256='16cbdac88d49c2f76eea461cf6c81e3866572f850fe29be726555549ac1c8f55'
readonly NVRAM_SHA256='3c4d7058803bd54d0443de0c272b6abd67e5f28f5ba11ecaf790331758f24cf4'

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

verify_file() {
  local path="$1" expected_sha="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] || fail "$label is missing or unsafe: $path"
  [[ "$(sha256_file "$path")" == "$expected_sha" ]] ||
    fail "$label has an unexpected SHA-256: $path"
}

fetch_file() {
  local source_filename="$1" target_filename="$2" expected_sha="$3" label="$4" target temporary_file
  target="$firmware_dir/$target_filename"
  if [[ -e "$target" || -L "$target" ]]; then
    verify_file "$target" "$expected_sha" "$label"
    return
  fi

  temporary_file="$(mktemp "$firmware_dir/.${target_filename}.XXXXXX")"
  if ! curl --fail --location --proto '=https' --silent --show-error --output "$temporary_file" \
    -- "$FIRMWARE_URL_BASE/$source_filename"; then
    rm -f -- "$temporary_file"
    fail "failed to download $label"
  fi
  verify_file "$temporary_file" "$expected_sha" "downloaded $label"
  mv -- "$temporary_file" "$target"
}

for required_command in curl dirname mkdir mktemp mv rm sha256sum; do
  command -v -- "$required_command" >/dev/null 2>&1 ||
    fail "required executable not found: $required_command"
done
if (($# != 0)); then
  fail 'usage: fetch-ap6335-firmware.sh'
fi
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
firmware_dir="$script_dir/artifacts/firmware/ap6335"
if [[ -e "$firmware_dir" || -L "$firmware_dir" ]]; then
  [[ -d "$firmware_dir" && ! -L "$firmware_dir" ]] || fail 'AP6335 firmware path is unsafe'
else
  mkdir -p -- "$(dirname -- "$firmware_dir")"
  mkdir -- "$firmware_dir"
fi

fetch_file 'fw_bcm4339a0_ag.bin' 'brcmfmac4339-sdio.bin' "$FIRMWARE_SHA256" 'AP6335 BCM4339 firmware'
fetch_file 'fw_bcm4339a0_ag.bin' 'brcmfmac4339-sdio.fsl,pico-imx7d.bin' "$FIRMWARE_SHA256" 'AP6335 board-specific BCM4339 firmware'
fetch_file 'nvram_ap6335.txt' 'brcmfmac4339-sdio.txt' "$NVRAM_SHA256" 'AP6335 BCM4339 NVRAM'
fetch_file 'nvram_ap6335.txt' 'brcmfmac4339-sdio.fsl,pico-imx7d.txt' "$NVRAM_SHA256" 'AP6335 board-specific BCM4339 NVRAM'
[[ ! -L "$firmware_dir/firmware.record" ]] || fail 'AP6335 firmware record path is unsafe'
temporary_record="$(mktemp "$firmware_dir/.firmware.record.XXXXXX")"
printf '%s\n' \
  'format=pico-imx7-ap6335-firmware-v1' \
  "firmware_commit=$FIRMWARE_COMMIT" \
  "firmware_sha256=$FIRMWARE_SHA256" \
  "nvram_sha256=$NVRAM_SHA256" > "$temporary_record"
mv -f -- "$temporary_record" "$firmware_dir/firmware.record"
printf 'fetched or verified AP6335 BCM4339 firmware: %s\n' "$firmware_dir"
