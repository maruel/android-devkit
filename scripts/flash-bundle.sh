#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

usage_flash() {
  printf '%s\n' \
    'usage: flash-bundle.sh --bundle /absolute/path/to/bundle [--flash' \
    '  --confirm-bundle FLASH_BUNDLE_SHA256=...' \
    '  --confirm-device FLASH_DEVICE=imx7d-sdp-VID:PID]' >&2
  exit 2
}

flash=false
bundle=""
confirm_bundle=""
confirm_device=""
while (($# > 0)); do
  case "$1" in
    --bundle) (($# >= 2)) || usage_flash; bundle="$2"; shift 2 ;;
    --flash) flash=true; shift ;;
    --confirm-bundle) (($# >= 2)) || usage_flash; confirm_bundle="$2"; shift 2 ;;
    --confirm-device) (($# >= 2)) || usage_flash; confirm_device="$2"; shift 2 ;;
    *) usage_flash ;;
  esac
done
[[ -n "$bundle" ]] || usage_flash
[[ "$bundle" == /* && -d "$bundle" && ! -L "$bundle" ]] || fail "--bundle must be an existing absolute directory"
manifest="$bundle/bundle.manifest"
require_regular_file "$manifest"
declare -A BUNDLE=()
expected_keys=(BUNDLE_VERSION CREATED_AT RAW_IMAGE_FILE RAW_IMAGE_SHA256 SPL_FILE SPL_SHA256 UBOOT_FILE UBOOT_SHA256 UUU_SCRIPT_FILE UUU_SCRIPT_SHA256 FLASH_EXPECTED_SDP_ID BOARD_EVIDENCE_PATH BOARD_EVIDENCE_SHA256 BOOT_EVIDENCE_PATH BOOT_EVIDENCE_SHA256 RAW_IMAGE_SOURCE SPL_SOURCE UBOOT_SOURCE UUU_SCRIPT_SOURCE)
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[A-Z][A-Z0-9_]*=[A-Za-z0-9._/:+=,@%\?\&~-]+$ ]] || fail "bundle manifest is malformed"
  key="${line%%=*}"
  value="${line#*=}"
  found=false
  for expected in "${expected_keys[@]}"; do [[ "$key" == "$expected" ]] && found=true; done
  "$found" || fail "bundle manifest has an unexpected field: $key"
  [[ ! -v "BUNDLE[$key]" ]] || fail "bundle manifest has a duplicate field: $key"
  BUNDLE["$key"]="$value"
done < "$manifest"
for key in "${expected_keys[@]}"; do [[ -v "BUNDLE[$key]" ]] || fail "bundle manifest is missing: $key"; done
[[ "${BUNDLE[BUNDLE_VERSION]}" == 1 ]] || fail "unsupported bundle manifest version"
for key in RAW_IMAGE_FILE SPL_FILE UBOOT_FILE UUU_SCRIPT_FILE; do
  [[ "${BUNDLE[$key]}" != */* && "${BUNDLE[$key]}" != .* ]] || fail "unsafe bundle filename"
done
require_distinct_values "bundle payload filenames" "${BUNDLE[RAW_IMAGE_FILE]}" "${BUNDLE[SPL_FILE]}" "${BUNDLE[UBOOT_FILE]}" "${BUNDLE[UUU_SCRIPT_FILE]}"
for reserved_name in bundle.manifest uuu-invocation.manifest logs; do
  for key in RAW_IMAGE_FILE SPL_FILE UBOOT_FILE UUU_SCRIPT_FILE; do
    [[ "${BUNDLE[$key]}" != "$reserved_name" ]] || fail "bundle payload filename is reserved for bundle metadata: $reserved_name"
  done
done
for key in RAW_IMAGE_SHA256 SPL_SHA256 UBOOT_SHA256 UUU_SCRIPT_SHA256; do
  [[ "${BUNDLE[$key]}" =~ ^[a-f0-9]{64}$ ]] || fail "invalid checksum in bundle manifest: $key"
done
for key in BOARD_EVIDENCE_SHA256 BOOT_EVIDENCE_SHA256; do
  [[ "${BUNDLE[$key]}" =~ ^[a-f0-9]{64}$ ]] || fail "invalid evidence checksum in bundle manifest: $key"
done
for key in BOARD_EVIDENCE_PATH BOOT_EVIDENCE_PATH; do
  [[ "${BUNDLE[$key]}" == /* && "${BUNDLE[$key]}" != / && "${BUNDLE[$key]}" != *'//'* && "${BUNDLE[$key]}" != */./* &&
     "${BUNDLE[$key]}" != */../* && "${BUNDLE[$key]}" != */. && "${BUNDLE[$key]}" != */.. ]] ||
    fail "unsafe evidence path in bundle manifest: $key"
done
identity="${BUNDLE[FLASH_EXPECTED_SDP_ID]}"
[[ "$identity" =~ ^imx7d-sdp-[a-f0-9]{4}:[a-f0-9]{4}$ ]] || fail "bundle does not declare an explicit i.MX7D SDP identity"
usb_id="${identity#imx7d-sdp-}"
usb_vid="${usb_id%%:*}"
usb_pid="${usb_id##*:}"
verify_sha256 "$bundle/${BUNDLE[RAW_IMAGE_FILE]}" "${BUNDLE[RAW_IMAGE_SHA256]}"
verify_sha256 "$bundle/${BUNDLE[SPL_FILE]}" "${BUNDLE[SPL_SHA256]}"
verify_sha256 "$bundle/${BUNDLE[UBOOT_FILE]}" "${BUNDLE[UBOOT_SHA256]}"
verify_sha256 "$bundle/${BUNDLE[UUU_SCRIPT_FILE]}" "${BUNDLE[UUU_SCRIPT_SHA256]}"
require_command uuu
require_command date
require_command awk
require_command sha256sum
require_command tee

discover_expected_path() {
  local discovery result matches sdp_family_rows path
  if ! discovery="$(uuu -lsusb)"; then
    fail "fresh uuu -lsusb discovery failed"
  fi
  result="$(printf '%s\n' "$discovery" | awk -v vid="$usb_vid" -v pid="$usb_pid" '
    function normalize(value) {
      value = tolower(value)
      sub(/^0x/, "", value)
      return value
    }
    $3 ~ /^SDP.*:$/ {
      sdp_family_rows++
      if ($3 == "SDP:" && $2 == "MX7D" && $4 ~ /^0[xX][0-9a-fA-F]+$/ && $5 ~ /^0[xX][0-9a-fA-F]+$/ && normalize($4) == vid && normalize($5) == pid) {
        matches++
        path = $1
      }
    }
    END { printf "%d\t%d\t%s\n", matches + 0, sdp_family_rows + 0, path }
  ')"
  IFS=$'\t' read -r matches sdp_family_rows path <<< "$result"
  [[ "$matches" == 1 && "$sdp_family_rows" == 1 && -n "$path" ]] ||
    fail "fresh discovery must contain exactly one expected i.MX7D SDP row ($identity); found $matches matching row(s) among $sdp_family_rows SDP-family row(s)"
  DISCOVERED_PATH="$path"
}

discover_expected_path
initial_path="$DISCOVERED_PATH"
bundle_hash="$(sha256sum -- "$manifest" | cut -d ' ' -f 1)"
required_bundle_confirmation="FLASH_BUNDLE_SHA256=$bundle_hash"
required_device_confirmation="FLASH_DEVICE=$identity"
if [[ "$flash" != true ]]; then
  printf 'dry run only; UUU will not be invoked to flash. Fresh discovery found %s.\n' "$identity"
  printf 'resolved UUU command: uuu -m %s %s\n' "$DISCOVERED_PATH" "$bundle/${BUNDLE[UUU_SCRIPT_FILE]}"
  printf 'payload RAW_IMAGE_FILE=%s SHA256=%s\n' "${BUNDLE[RAW_IMAGE_FILE]}" "${BUNDLE[RAW_IMAGE_SHA256]}"
  printf 'payload SPL_FILE=%s SHA256=%s\n' "${BUNDLE[SPL_FILE]}" "${BUNDLE[SPL_SHA256]}"
  printf 'payload UBOOT_FILE=%s SHA256=%s\n' "${BUNDLE[UBOOT_FILE]}" "${BUNDLE[UBOOT_SHA256]}"
  printf 'payload UUU_SCRIPT_FILE=%s SHA256=%s\n' "${BUNDLE[UUU_SCRIPT_FILE]}" "${BUNDLE[UUU_SCRIPT_SHA256]}"
  printf 'to flash, add --flash --confirm-bundle %s --confirm-device %s\n' \
    "$required_bundle_confirmation" "$required_device_confirmation"
  exit 0
fi
[[ "$confirm_bundle" == "$required_bundle_confirmation" ]] || fail "first operator confirmation does not match this bundle"
[[ "$confirm_device" == "$required_device_confirmation" ]] || fail "second operator confirmation does not match discovered device identity"
discover_expected_path
[[ "$DISCOVERED_PATH" == "$initial_path" ]] ||
  fail "fresh discovery changed expected i.MX7D SDP path before flashing"
logs_dir="$bundle/logs"
[[ ! -L "$logs_dir" ]] || fail "flash logs path must not be a symbolic link"
if [[ ! -e "$logs_dir" ]]; then mkdir -- "$logs_dir"; fi
[[ -d "$logs_dir" && ! -L "$logs_dir" ]] || fail "flash logs path is unsafe"
snapshot="$(mktemp -d "$bundle/.flash-snapshot.XXXXXX")"
# shellcheck disable=SC2317
cleanup_snapshot() { rm -rf -- "$snapshot"; }
trap cleanup_snapshot EXIT
for payload_key in RAW_IMAGE_FILE SPL_FILE UBOOT_FILE UUU_SCRIPT_FILE; do
  cp -- "$bundle/${BUNDLE[$payload_key]}" "$snapshot/${BUNDLE[$payload_key]}"
done
verify_sha256 "$snapshot/${BUNDLE[RAW_IMAGE_FILE]}" "${BUNDLE[RAW_IMAGE_SHA256]}"
verify_sha256 "$snapshot/${BUNDLE[SPL_FILE]}" "${BUNDLE[SPL_SHA256]}"
verify_sha256 "$snapshot/${BUNDLE[UBOOT_FILE]}" "${BUNDLE[UBOOT_SHA256]}"
verify_sha256 "$snapshot/${BUNDLE[UUU_SCRIPT_FILE]}" "${BUNDLE[UUU_SCRIPT_SHA256]}"
flash_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$(mktemp -d "${logs_dir}/run-${flash_timestamp}.XXXXXX")"
log="$run_dir/uuu.log"
printf 'flashing %s after two operator confirmations; log: %s\n' "$identity" "$log"
if uuu -m "$DISCOVERED_PATH" "$snapshot/${BUNDLE[UUU_SCRIPT_FILE]}" 2>&1 | tee -- "$log"; then
  pipeline_status=("${PIPESTATUS[@]}")
else
  pipeline_status=("${PIPESTATUS[@]}")
fi
uuu_status="${pipeline_status[0]}"
tee_status="${pipeline_status[1]}"
write_text_record "$run_dir/result" \
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command=uuu-m-path-bundle-script" \
  "bundle_manifest_sha256=$bundle_hash" "device=$identity" "device_path=$DISCOVERED_PATH" \
  "uuu_exit_code=$uuu_status" "tee_exit_code=$tee_status" "log=$log"
if [[ "$tee_status" != 0 ]]; then
  fail "UUU output logging failed (tee exit $tee_status; UUU exit $uuu_status)"
fi
exit "$uuu_status"
