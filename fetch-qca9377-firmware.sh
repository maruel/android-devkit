#!/usr/bin/env bash
set -euo pipefail

readonly FIRMWARE_COMMIT='16d815da3637f645bc67e4c71b757e70ae44d498'
readonly FIRMWARE_URL_BASE='https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/QCA9377/hw1.0'
readonly BOARD_SHA256='127d35d82edb46278f30c448cbca664d755ff0d5fed57b649959cdbc4208c768'
readonly BOARD_2_SHA256='0fdcc7838f478da81704de88f7b33e28862110c6d5decf7818543f8e37e6cd98'
readonly FIRMWARE_SDIO_5_SHA256='017b4ae7bdb5821ecb439fbf96d198421a57926918f2513db5fbd6d9c01debe6'

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
  local filename="$1" expected_sha="$2" label="$3" target temporary_file
  target="$firmware_dir/$filename"
  if [[ -e "$target" || -L "$target" ]]; then
    verify_file "$target" "$expected_sha" "$label"
    return
  fi

  temporary_file="$(mktemp "$firmware_dir/.${filename}.XXXXXX")"
  if ! curl --fail --location --proto '=https' --silent --show-error --output "$temporary_file" \
    -- "$FIRMWARE_URL_BASE/$filename?id=$FIRMWARE_COMMIT"; then
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
  fail 'usage: fetch-qca9377-firmware.sh'
fi
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
firmware_dir="$script_dir/artifacts/firmware/qca9377"
if [[ -e "$firmware_dir" || -L "$firmware_dir" ]]; then
  [[ -d "$firmware_dir" && ! -L "$firmware_dir" ]] || fail 'QCA9377 firmware path is unsafe'
else
  mkdir -p -- "$(dirname -- "$firmware_dir")"
  mkdir -- "$firmware_dir"
fi

fetch_file 'board.bin' "$BOARD_SHA256" 'QCA9377 fallback board data'
fetch_file 'board-2.bin' "$BOARD_2_SHA256" 'QCA9377 board data'
fetch_file 'firmware-sdio-5.bin' "$FIRMWARE_SDIO_5_SHA256" 'QCA9377 SDIO firmware'
[[ ! -L "$firmware_dir/firmware.record" ]] || fail 'QCA9377 firmware record path is unsafe'
temporary_record="$(mktemp "$firmware_dir/.firmware.record.XXXXXX")"
printf '%s\n' \
  'format=pico-imx7-qca9377-firmware-v1' \
  "firmware_commit=$FIRMWARE_COMMIT" \
  "board_sha256=$BOARD_SHA256" \
  "board_2_sha256=$BOARD_2_SHA256" \
  "firmware_sdio_5_sha256=$FIRMWARE_SDIO_5_SHA256" > "$temporary_record"
mv -f -- "$temporary_record" "$firmware_dir/firmware.record"
printf 'fetched or verified QCA9377 SDIO firmware: %s\n' "$firmware_dir"
