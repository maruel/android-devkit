#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

bundle_name() {
  local key="$1" value resolved_name
  require_relative_path resolved_name "$key"
  value="$resolved_name"
  [[ "$value" != */* ]] || fail "$key must be a single explicit filename"
  BUNDLE_NAME="$value"
}

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare bundle_dir raw_image spl uboot uuu_script raw_sha spl_sha uboot_sha uuu_sha raw_name spl_name uboot_name uuu_name sdp_identity BUNDLE_NAME
declare board_evidence_path board_evidence_sha boot_evidence_path boot_evidence_sha checkout artifacts_root
require_clean_absolute_path checkout KERNEL_CHECKOUT_DIR
require_clean_absolute_path artifacts_root ARTIFACTS_ROOT
require_resolved_path_under bundle_dir BUNDLE_DIR ARTIFACTS_ROOT
require_paths_outside "$checkout" "kernel checkout and generated paths" "$artifacts_root" "$bundle_dir"
new_output_path "$bundle_dir"
require_clean_absolute_path raw_image RAW_IMAGE_PATH
require_clean_absolute_path spl SPL_PATH
require_clean_absolute_path uboot UBOOT_PATH
require_clean_absolute_path uuu_script UUU_SCRIPT_PATH
require_sha256 raw_sha RAW_IMAGE_SHA256
require_sha256 spl_sha SPL_SHA256
require_sha256 uboot_sha UBOOT_SHA256
require_sha256 uuu_sha UUU_SCRIPT_SHA256
bundle_name BUNDLE_RAW_IMAGE_NAME; raw_name="$BUNDLE_NAME"
bundle_name BUNDLE_SPL_NAME; spl_name="$BUNDLE_NAME"
bundle_name BUNDLE_UBOOT_NAME; uboot_name="$BUNDLE_NAME"
bundle_name BUNDLE_UUU_SCRIPT_NAME; uuu_name="$BUNDLE_NAME"
require_distinct_values "bundle payload filenames" "$raw_name" "$spl_name" "$uboot_name" "$uuu_name"
for reserved_name in bundle.manifest uuu-invocation.manifest logs; do
  [[ "$raw_name" != "$reserved_name" && "$spl_name" != "$reserved_name" && "$uboot_name" != "$reserved_name" && "$uuu_name" != "$reserved_name" ]] ||
    fail "bundle payload filename is reserved for bundle metadata: $reserved_name"
done
require_field sdp_identity FLASH_EXPECTED_SDP_ID
[[ "$sdp_identity" =~ ^imx7d-sdp-[a-f0-9]{4}:[a-f0-9]{4}$ ]] ||
  fail "FLASH_EXPECTED_SDP_ID must explicitly identify imx7d-sdp-VID:PID"
require_regular_file "$raw_image"
require_clean_absolute_path board_evidence_path BOARD_EVIDENCE_PATH
require_sha256 board_evidence_sha BOARD_EVIDENCE_SHA256
require_clean_absolute_path boot_evidence_path BOOT_EVIDENCE_PATH
require_sha256 boot_evidence_sha BOOT_EVIDENCE_SHA256
require_command sha256sum
verify_sha256 "$board_evidence_path" "$board_evidence_sha"
verify_sha256 "$boot_evidence_path" "$boot_evidence_sha"
require_regular_file "$spl"
require_regular_file "$uboot"
require_regular_file "$uuu_script"
require_command date
verify_sha256 "$raw_image" "$raw_sha"
verify_sha256 "$spl" "$spl_sha"
verify_sha256 "$uboot" "$uboot_sha"
verify_sha256 "$uuu_script" "$uuu_sha"
parent="$(dirname -- "$bundle_dir")"
mkdir -p -- "$parent"
temporary="$(mktemp -d "${parent}/.flash-bundle.XXXXXX")"
cleanup() { rm -rf -- "$temporary"; }
trap cleanup EXIT
cp -- "$raw_image" "$temporary/$raw_name"
cp -- "$spl" "$temporary/$spl_name"
cp -- "$uboot" "$temporary/$uboot_name"
cp -- "$uuu_script" "$temporary/$uuu_name"
write_text_record "$temporary/bundle.manifest" \
  "BUNDLE_VERSION=1" "CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "RAW_IMAGE_FILE=$raw_name" "RAW_IMAGE_SHA256=$raw_sha" \
  "SPL_FILE=$spl_name" "SPL_SHA256=$spl_sha" "UBOOT_FILE=$uboot_name" "UBOOT_SHA256=$uboot_sha" \
  "UUU_SCRIPT_FILE=$uuu_name" "UUU_SCRIPT_SHA256=$uuu_sha" \
  "FLASH_EXPECTED_SDP_ID=$sdp_identity" "BOARD_EVIDENCE_PATH=$board_evidence_path" "BOARD_EVIDENCE_SHA256=$board_evidence_sha" \
  "BOOT_EVIDENCE_PATH=$boot_evidence_path" "BOOT_EVIDENCE_SHA256=$boot_evidence_sha" "RAW_IMAGE_SOURCE=$raw_image" \
  "SPL_SOURCE=$spl" "UBOOT_SOURCE=$uboot" "UUU_SCRIPT_SOURCE=$uuu_script"
write_text_record "$temporary/uuu-invocation.manifest" \
  "COMMAND=uuu ./$uuu_name" "RAW_IMAGE=$raw_name" "SPL=$spl_name" "UBOOT=$uboot_name"
mv -T -- "$temporary" "$bundle_dir"
trap - EXIT
printf 'created checksummed image/flash bundle (not a boot-tested device image): %s\n' "$bundle_dir"
