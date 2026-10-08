#!/usr/bin/env bash
# Build and publish modules from validated kernel configuration and source evidence.
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare checkout build_dir config kernel_build_root module_stage_dir publication_dir publication_parent publication_stage module_record resolved_stage_dir resolved_build_root stage_temporary architecture cross_compile target_release wifi_dir camera_dir commit identity_record config_sha_record configure_record artifacts_root config_output_root
declare board_evidence_sha wifi_evidence_sha camera_evidence_sha wifi_fragment_sha camera_fragment_sha source_config_sha wifi_checkout_dir camera_checkout_dir wifi_stage_dir camera_stage_dir
stage_temporary=""
publication_stage=""
module_stage_created=false

read_module_list() {
  local key="$1" value module
  require_field value "$key"
  declare -ga MODULE_LIST=()
  IFS=',' read -r -a MODULE_LIST <<< "$value"
  ((${#MODULE_LIST[@]} > 0)) || fail "$key must name at least one module"
  local -A seen_modules=()
  for module in "${MODULE_LIST[@]}"; do
    [[ "$module" =~ ^[A-Za-z0-9_.-]+\.ko$ && "$module" != .* ]] ||
      fail "$key must be an ordered comma-separated list of .ko filenames"
    [[ ! -v "seen_modules[$module]" ]] || fail "$key contains a duplicate module: $module"
    seen_modules["$module"]=1
  done
}

require_resolved_path_under checkout KERNEL_CHECKOUT_DIR KERNEL_BUILD_ROOT
require_resolved_path_under build_dir KERNEL_BUILD_DIR KERNEL_BUILD_ROOT
require_clean_absolute_path kernel_build_root KERNEL_BUILD_ROOT
module_stage_dir="$kernel_build_root/module-source-stage"
[[ "$module_stage_dir" != "$checkout" && "$module_stage_dir" != "$checkout"/* ]] ||
  fail "module source staging directory must not be inside KERNEL_CHECKOUT_DIR"
require_command realpath
resolved_stage_dir="$(realpath -m -- "$module_stage_dir")"
resolved_build_root="$(realpath -m -- "$kernel_build_root")"
[[ "$resolved_stage_dir" == "$resolved_build_root"/* ]] || fail "module source staging directory resolves outside KERNEL_BUILD_ROOT"
require_field architecture ARCH
require_field cross_compile CROSS_COMPILE
require_field target_release KERNEL_TARGET_RELEASE
require_commit_sha commit
require_resolved_path_under identity_record KERNEL_IDENTITY_RECORD_PATH KERNEL_BUILD_ROOT
require_resolved_path_under config_sha_record CONFIG_SHA256_RECORD_PATH CONFIG_OUTPUT_ROOT
require_resolved_path_under config CONFIG_DESTINATION CONFIG_OUTPUT_ROOT
require_resolved_path_under configure_record CONFIGURE_RECORD_PATH ARTIFACTS_ROOT
require_clean_absolute_path artifacts_root ARTIFACTS_ROOT
require_clean_absolute_path config_output_root CONFIG_OUTPUT_ROOT
require_sha256 board_evidence_sha BOARD_EVIDENCE_SHA256
require_sha256 wifi_evidence_sha WIFI_EVIDENCE_SHA256
require_sha256 camera_evidence_sha CAMERA_EVIDENCE_SHA256
require_sha256 wifi_fragment_sha WIFI_KCONFIG_FRAGMENT_SHA256
require_sha256 camera_fragment_sha CAMERA_KCONFIG_FRAGMENT_SHA256
verify_evidence BOARD_EVIDENCE_PATH BOARD_EVIDENCE_SHA256
verify_evidence WIFI_EVIDENCE_PATH WIFI_EVIDENCE_SHA256
verify_evidence CAMERA_EVIDENCE_PATH CAMERA_EVIDENCE_SHA256
require_relative_path wifi_dir WIFI_MODULE_DIR
require_relative_path camera_dir CAMERA_MODULE_DIR
require_resolved_path_under publication_dir MODULE_PUBLICATION_DIR ARTIFACTS_ROOT
module_record="$publication_dir/modules.record"
require_paths_outside "$checkout" "kernel checkout and generated paths" "$artifacts_root" "$config_output_root" "$build_dir" "$config" "$config_sha_record" "$configure_record" "$identity_record" "$module_stage_dir" "$publication_dir" "$module_record"
require_non_overlapping_paths "module outputs" "$build_dir" "$module_stage_dir" "$publication_dir"
require_non_overlapping_paths "module outputs" "$build_dir" "$module_stage_dir" "$module_record"
new_output_path "$publication_dir"
new_output_path "$module_stage_dir"
read_module_list WIFI_MODULE_KOS
wifi_modules=("${MODULE_LIST[@]}")
read_module_list CAMERA_MODULE_KOS
camera_modules=("${MODULE_LIST[@]}")
declare -A declared_module_outputs=()
for module in "${wifi_modules[@]}"; do
  declared_module_outputs["$module"]=wifi
done
for module in "${camera_modules[@]}"; do
  [[ ! -v "declared_module_outputs[$module]" ]] ||
    fail "Wi-Fi and camera module output names must be distinct: $module"
  declared_module_outputs["$module"]=camera
done
require_regular_file "$checkout/Makefile"
require_regular_file "$build_dir/.config"
require_command sha256sum
verify_config_record "$config" "$config_sha_record"
source_config_sha="$(sha256sum -- "$config")"
source_config_sha="${source_config_sha%% *}"
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
verify_configure_record "$configure_record" "$config" "$build_dir/.config" "$commit" "$board_evidence_sha" "$wifi_evidence_sha" "$camera_evidence_sha" "$wifi_fragment_sha" "$camera_fragment_sha"
resolve_relative_path_under wifi_checkout_dir "$wifi_dir" "$checkout" WIFI_MODULE_DIR KERNEL_CHECKOUT_DIR
resolve_relative_path_under camera_checkout_dir "$camera_dir" "$checkout" CAMERA_MODULE_DIR KERNEL_CHECKOUT_DIR
[[ -d "$wifi_checkout_dir" ]] || fail "Wi-Fi module source directory does not exist: $wifi_dir"
[[ -d "$camera_checkout_dir" ]] || fail "camera module source directory does not exist: $camera_dir"
require_command make
require_command date
require_command cp
for module in "${wifi_modules[@]}"; do
  [[ ! -e "$checkout/$wifi_dir/$module" ]] || fail "kernel checkout contains stale Wi-Fi module output: $wifi_dir/$module"
done
for module in "${camera_modules[@]}"; do
  [[ ! -e "$checkout/$camera_dir/$module" ]] || fail "kernel checkout contains stale camera module output: $camera_dir/$module"
done
mkdir -p -- "$kernel_build_root"
cleanup() {
  [[ -z "$stage_temporary" ]] || rm -rf -- "$stage_temporary"
  [[ -z "$publication_stage" ]] || rm -rf -- "$publication_stage"
  [[ "$module_stage_created" != true ]] || rm -rf -- "$module_stage_dir"
}
trap cleanup EXIT
stage_temporary="$(mktemp -d "${kernel_build_root}/.module-source-stage.XXXXXX")"
cp -a -- "$checkout/." "$stage_temporary"
mv -T -- "$stage_temporary" "$module_stage_dir"
stage_temporary=""
module_stage_created=true
require_regular_file "$module_stage_dir/Makefile"
resolve_relative_path_under wifi_stage_dir "$wifi_dir" "$module_stage_dir" WIFI_MODULE_DIR module-source-stage
resolve_relative_path_under camera_stage_dir "$camera_dir" "$module_stage_dir" CAMERA_MODULE_DIR module-source-stage
[[ -d "$wifi_stage_dir" ]] || fail "Wi-Fi module source directory does not exist in module staging: $wifi_dir"
[[ -d "$camera_stage_dir" ]] || fail "camera module source directory does not exist in module staging: $camera_dir"
actual_release="$(make -s -C "$module_stage_dir" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" kernelrelease)"
[[ "$actual_release" == "$target_release" ]] ||
  fail "kernel release mismatch: declared $target_release, make reported ${actual_release:-nothing}"
make -C "$module_stage_dir" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" M="$wifi_dir" modules
make -C "$module_stage_dir" O="$build_dir" ARCH="$architecture" CROSS_COMPILE="$cross_compile" M="$camera_dir" modules
publication_parent="$(dirname -- "$publication_dir")"
mkdir -p -- "$publication_parent"
publication_stage="$(mktemp -d "${publication_parent}/.module-publication.XXXXXX")"
mkdir -- "$publication_stage/wifi" "$publication_stage/camera"
record_lines=(
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command_wifi=make-M-$wifi_dir-modules" \
  "command_camera=make-M-$camera_dir-modules" "target_release=$target_release" "kernelrelease=$actual_release" \
  "wifi_source_dir=$wifi_dir" "camera_source_dir=$camera_dir" "module_stage_dir=$module_stage_dir" \
  "kernel_commit=$commit" "board_evidence_sha256=$board_evidence_sha" "wifi_evidence_sha256=$wifi_evidence_sha" \
  "camera_evidence_sha256=$camera_evidence_sha" "wifi_fragment_sha256=$wifi_fragment_sha" \
  "camera_fragment_sha256=$camera_fragment_sha" "source_config_sha256=$source_config_sha" \
  "merged_config_sha256=$(sha256sum -- "$build_dir/.config" | cut -d ' ' -f 1)"
)
for module in "${wifi_modules[@]}"; do
  module_output="$module_stage_dir/$wifi_dir/$module"
  require_regular_file "$module_output"
  [[ ! -e "$checkout/$wifi_dir/$module" ]] || fail "kernel checkout changed during Wi-Fi module build: $wifi_dir/$module"
  cp -- "$module_output" "$publication_stage/wifi/$module"
  record_lines+=("wifi_module=$module" "wifi_artifact=$publication_dir/wifi/$module" "wifi_sha256=$(sha256sum -- "$publication_stage/wifi/$module" | cut -d ' ' -f 1)")
done
for module in "${camera_modules[@]}"; do
  module_output="$module_stage_dir/$camera_dir/$module"
  require_regular_file "$module_output"
  [[ ! -e "$checkout/$camera_dir/$module" ]] || fail "kernel checkout changed during camera module build: $camera_dir/$module"
  cp -- "$module_output" "$publication_stage/camera/$module"
  record_lines+=("camera_module=$module" "camera_artifact=$publication_dir/camera/$module" "camera_sha256=$(sha256sum -- "$publication_stage/camera/$module" | cut -d ' ' -f 1)")
done
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
write_text_record "$publication_stage/modules.record" "${record_lines[@]}"
verify_kernel_checkout "$checkout" "$commit" "$identity_record"
mv -T -- "$publication_stage" "$publication_dir"
publication_stage=""
trap - EXIT
printf 'built and copied selected Wi-Fi and camera modules without installing them\n'
