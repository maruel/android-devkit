#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare checkout build_dir config config_sha_record wifi_fragment camera_fragment architecture cross_compile target_release record commit identity_record build_config artifacts_root config_output_root
declare board_evidence_sha wifi_evidence_sha camera_evidence_sha wifi_fragment_sha camera_fragment_sha source_config_sha merged_config_sha
require_resolved_path_under checkout KERNEL_CHECKOUT_DIR KERNEL_BUILD_ROOT
require_resolved_path_under build_dir KERNEL_BUILD_DIR KERNEL_BUILD_ROOT
[[ "$build_dir" != "$checkout" && "$build_dir" != "$checkout"/* ]] ||
  fail "KERNEL_BUILD_DIR must not be inside the source checkout"
require_resolved_path_under config CONFIG_DESTINATION CONFIG_OUTPUT_ROOT
require_resolved_path_under config_sha_record CONFIG_SHA256_RECORD_PATH CONFIG_OUTPUT_ROOT
require_clean_absolute_path artifacts_root ARTIFACTS_ROOT
require_clean_absolute_path config_output_root CONFIG_OUTPUT_ROOT
require_clean_absolute_path wifi_fragment WIFI_KCONFIG_FRAGMENT
require_clean_absolute_path camera_fragment CAMERA_KCONFIG_FRAGMENT
require_sha256 wifi_fragment_sha WIFI_KCONFIG_FRAGMENT_SHA256
require_sha256 camera_fragment_sha CAMERA_KCONFIG_FRAGMENT_SHA256
require_sha256 board_evidence_sha BOARD_EVIDENCE_SHA256
require_sha256 wifi_evidence_sha WIFI_EVIDENCE_SHA256
require_sha256 camera_evidence_sha CAMERA_EVIDENCE_SHA256
require_field architecture ARCH
require_field cross_compile CROSS_COMPILE
require_field target_release KERNEL_TARGET_RELEASE
require_commit_sha commit
require_resolved_path_under identity_record KERNEL_IDENTITY_RECORD_PATH KERNEL_BUILD_ROOT
require_resolved_path_under record CONFIGURE_RECORD_PATH ARTIFACTS_ROOT
build_config="$build_dir/.config"
require_paths_outside "$checkout" "kernel checkout and generated paths" "$artifacts_root" "$config_output_root" "$build_dir" "$config" "$config_sha_record" "$record" "$identity_record"
require_non_overlapping_paths "kernel configuration outputs" "$build_dir" "$record"
require_non_overlapping_paths "kernel configuration outputs" "$build_config" "$record"
new_output_path "$build_config"
new_output_path "$record"
require_command sha256sum
require_regular_file "$config"
verify_config_record "$config" "$config_sha_record"
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
verify_evidence BOARD_EVIDENCE_PATH BOARD_EVIDENCE_SHA256
verify_evidence WIFI_EVIDENCE_PATH WIFI_EVIDENCE_SHA256
verify_evidence CAMERA_EVIDENCE_PATH CAMERA_EVIDENCE_SHA256
require_regular_file "$wifi_fragment"
require_regular_file "$camera_fragment"
verify_sha256 "$wifi_fragment" "$wifi_fragment_sha"
verify_sha256 "$camera_fragment" "$camera_fragment_sha"
require_regular_file "$checkout/Makefile"
require_regular_file "$checkout/scripts/kconfig/merge_config.sh"
require_command make
require_command date
source_config_sha="$(sha256sum -- "$config")"
source_config_sha="${source_config_sha%% *}"
mkdir -p -- "$build_dir" "$(dirname -- "$record")"
cp -- "$config" "$build_dir/.config"
"$checkout/scripts/kconfig/merge_config.sh" -m -O "$build_dir" \
  "$build_dir/.config" "$wifi_fragment" "$camera_fragment"
make -C "$checkout" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" olddefconfig
make -C "$checkout" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" prepare
make -C "$checkout" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" modules_prepare
verify_fragment_entries() {
  local fragment="$1" line symbol expected actual
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^CONFIG_[A-Za-z0-9_]+= ]]; then
      symbol="${line%%=*}"
    elif [[ "$line" =~ ^\#\ CONFIG_[A-Za-z0-9_]+\ is\ not\ set$ ]]; then
      symbol="${line#\# }"
      symbol="${symbol%% *}"
    else
      continue
    fi
    expected="$line"
    actual="$(grep -E "^(# )?${symbol}(=| is not set$)" -- "$build_dir/.config" || true)"
    [[ "$actual" == "$expected" ]] ||
      fail "fragment symbol was dropped or changed by configuration: $symbol"
  done < "$fragment"
}
verify_fragment_entries "$wifi_fragment"
verify_fragment_entries "$camera_fragment"
actual_release="$(make -s -C "$checkout" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" kernelrelease)"
[[ -n "$actual_release" ]] || fail "make -s kernelrelease did not determine a target release"
[[ "$actual_release" == "$target_release" ]] ||
  fail "kernel release mismatch: declared $target_release, make reported $actual_release"
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
merged_config_sha="$(sha256sum -- "$build_dir/.config")"
merged_config_sha="${merged_config_sha%% *}"
write_text_record "$record" \
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "command=merge-config-and-olddefconfig" "command_prepare=make-prepare" \
  "command_modules_prepare=make-modules_prepare" "checkout=$checkout" "config=$config" "source_config_sha256=$source_config_sha" \
  "merged_config=$build_dir/.config" "merged_config_sha256=$merged_config_sha" "kernel_commit=$commit" \
  "board_evidence_sha256=$board_evidence_sha" "wifi_evidence_sha256=$wifi_evidence_sha" \
  "camera_evidence_sha256=$camera_evidence_sha" "wifi_fragment=$wifi_fragment" "wifi_fragment_sha256=$wifi_fragment_sha" \
  "camera_fragment=$camera_fragment" "camera_fragment_sha256=$camera_fragment_sha" "arch=$architecture" "cross_compile=$cross_compile" \
  "target_release=$target_release" "kernelrelease=$actual_release" "build_dir=$build_dir"
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
verify_configure_record "$record" "$config" "$build_config" "$commit" "$board_evidence_sha" "$wifi_evidence_sha" "$camera_evidence_sha" "$wifi_fragment_sha" "$camera_fragment_sha"
printf 'configured kernel build directory: %s\n' "$build_dir"
