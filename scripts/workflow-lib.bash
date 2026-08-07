#!/usr/bin/env bash
# Shared strict-manifest and filesystem helpers for the phase-2 workflow.

set -euo pipefail

readonly WORKFLOW_FIELDS=(
  ARCH ARTIFACTS_ROOT BASE_IMAGE_DECOMPRESS BASE_IMAGE_DECOMPRESSED_DESTINATION
  BOARD_EVIDENCE_PATH BOARD_EVIDENCE_SHA256 BOOT_EVIDENCE_PATH BOOT_EVIDENCE_SHA256
  BASE_IMAGE_DESTINATION BASE_IMAGE_RELEASE BASE_IMAGE_SHA256 BASE_IMAGE_URL
  BUNDLE_DIR BUNDLE_RAW_IMAGE_NAME BUNDLE_SPL_NAME BUNDLE_UBOOT_NAME
  BUNDLE_UUU_SCRIPT_NAME CAMERA_EVIDENCE_PATH CAMERA_EVIDENCE_SHA256 CAMERA_KCONFIG_FRAGMENT
  CAMERA_KCONFIG_FRAGMENT_SHA256 CAMERA_MODULE_DIR CAMERA_MODULE_KOS CONFIG_ARCHIVE_OUTPUT CONFIG_ARCHIVE_PATH
  CONFIG_ARCHIVE_SHA256 CONFIG_DESTINATION CONFIG_OUTPUT_ROOT CONFIG_SOURCE
  CONFIG_SSH_HOST CONFIG_SSH_PORT CONFIG_SSH_REMOTE_PATH CONFIG_SSH_USER
  CONFIGURE_RECORD_PATH CONFIG_SHA256_RECORD_PATH CROSS_COMPILE FLASH_EXPECTED_SDP_ID KERNEL_BUILD_DIR
  KERNEL_BUILD_ROOT KERNEL_CHECKOUT_DIR KERNEL_COMMIT_SHA KERNEL_IDENTITY_RECORD_PATH KERNEL_REPO_URL
  KERNEL_TARGET_RELEASE MODULE_PUBLICATION_DIR RAW_IMAGE_PATH RAW_IMAGE_SHA256
  SPL_PATH SPL_SHA256 UBOOT_PATH UBOOT_SHA256 UUU_SCRIPT_PATH UUU_SCRIPT_SHA256
  WIFI_EVIDENCE_PATH WIFI_EVIDENCE_SHA256 WIFI_KCONFIG_FRAGMENT WIFI_KCONFIG_FRAGMENT_SHA256 WIFI_MODULE_DIR WIFI_MODULE_KOS
)

declare -A MANIFEST=()

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage_manifest() {
  printf 'usage: %s --manifest /absolute/path/to/manifest [options]\n' "${0##*/}" >&2
  exit 2
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

is_known_field() {
  local field
  for field in "${WORKFLOW_FIELDS[@]}"; do
    [[ "$field" == "$1" ]] && return 0
  done
  return 1
}

parse_manifest() {
  local manifest_path="$1"
  local line key value
  [[ -f "$manifest_path" ]] || fail "manifest is not a regular file: $manifest_path"
  [[ ! -L "$manifest_path" ]] || fail "manifest must not be a symbolic link: $manifest_path"
  MANIFEST=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*=[A-Za-z0-9._/:+=,@%\?\&~-]+$ ]] ||
      fail "manifest has a comment, empty value, malformed field, or unsafe value"
    key="${line%%=*}"
    value="${line#*=}"
    is_known_field "$key" || fail "manifest contains unexpected field: $key"
    [[ -v "MANIFEST[$key]" ]] && fail "manifest contains duplicate field: $key"
    MANIFEST["$key"]="$value"
  done < "$manifest_path"
  ((${#MANIFEST[@]} > 0)) || fail "manifest is empty"
}

value_is_placeholder() {
  [[ "$1" == *PLACEHOLDER* ]] ||
    [[ "$1" =~ (^|[_-])(CHANGEME|REPLACE|TODO)([_-]|$) ]] ||
    [[ "$1" == *"example.invalid"* ]]
}

require_field() {
  local output_name="$1" key="$2" raw_value
  [[ -v "MANIFEST[$key]" ]] || fail "manifest is missing required field: $key"
  raw_value="${MANIFEST[$key]}"
  [[ -n "$raw_value" ]] || fail "manifest field is empty: $key"
  value_is_placeholder "$raw_value" && fail "manifest field remains a placeholder: $key"
  printf -v "$output_name" '%s' "$raw_value"
}

require_sha256() {
  local output_name="$1" key="$2" __workflow_value
  require_field __workflow_value "$key"
  [[ "$__workflow_value" =~ ^[a-f0-9]{64}$ ]] || fail "$key must be a lowercase 64-character SHA-256"
  printf -v "$output_name" '%s' "$__workflow_value"
}

require_commit_sha() {
  local output_name="$1" __workflow_value
  require_field __workflow_value KERNEL_COMMIT_SHA
  [[ "$__workflow_value" =~ ^[a-f0-9]{40}$ ]] || fail "KERNEL_COMMIT_SHA must be a full lowercase 40-character commit SHA"
  printf -v "$output_name" '%s' "$__workflow_value"
}

require_clean_absolute_path() {
  local output_name="$1" key="$2" __workflow_value
  require_field __workflow_value "$key"
  [[ "$__workflow_value" == /* && "$__workflow_value" != / && "$__workflow_value" != *'//'* && "$__workflow_value" != */./* &&
     "$__workflow_value" != */../* && "$__workflow_value" != */. && "$__workflow_value" != */.. ]] ||
    fail "$key must be a clean absolute path"
  printf -v "$output_name" '%s' "$__workflow_value"
}

require_relative_path() {
  local output_name="$1" key="$2" __workflow_value
  require_field __workflow_value "$key"
  [[ "$__workflow_value" != /* && "$__workflow_value" != *'//'* && "$__workflow_value" != */./* && "$__workflow_value" != */../* &&
     "$__workflow_value" != . && "$__workflow_value" != .. && "$__workflow_value" != *'..'* ]] ||
    fail "$key must be a safe relative path"
  printf -v "$output_name" '%s' "$__workflow_value"
}

require_path_under() {
  local output_name="$1" path_key="$2" root_key="$3" __workflow_path __workflow_root
  require_clean_absolute_path __workflow_path "$path_key"
  require_clean_absolute_path __workflow_root "$root_key"
  [[ "$__workflow_path" == "$__workflow_root" || "$__workflow_path" == "$__workflow_root"/* ]] ||
    fail "$path_key must be beneath $root_key"
  printf -v "$output_name" '%s' "$__workflow_path"
}

require_resolved_path_under() {
  local output_name="$1" path_key="$2" root_key="$3" candidate_path candidate_root resolved_path resolved_root
  require_path_under candidate_path "$path_key" "$root_key"
  require_clean_absolute_path candidate_root "$root_key"
  require_command realpath
  resolved_path="$(realpath -m -- "$candidate_path")"
  resolved_root="$(realpath -m -- "$candidate_root")"
  [[ "$resolved_path" == "$resolved_root" || "$resolved_path" == "$resolved_root"/* ]] ||
    fail "$path_key resolves outside $root_key through a symbolic link"
  printf -v "$output_name" '%s' "$candidate_path"
}

require_distinct_values() {
  local description="$1" value
  shift
  local -A seen_values=()
  for value in "$@"; do
    [[ -n "$value" ]] || continue
    [[ ! -v "seen_values[$value]" ]] || fail "$description must be distinct: $value"
    seen_values["$value"]=1
  done
}

require_non_overlapping_paths() {
  local description="$1" left right resolved_left resolved_right
  shift
  require_command realpath
  while (($# > 1)); do
    left="$1"
    shift
    [[ -n "$left" ]] || continue
    for right in "$@"; do
      [[ -n "$right" ]] || continue
      resolved_left="$(realpath -m -- "$left")"
      resolved_right="$(realpath -m -- "$right")"
      [[ "$resolved_left" != "$resolved_right" && "$resolved_left" != "$resolved_right"/* && "$resolved_right" != "$resolved_left"/* ]] ||
        fail "$description must not overlap: $left and $right"
    done
  done
}

require_paths_outside() {
  local protected_path="$1" description="$2" candidate_path resolved_protected resolved_candidate
  shift 2
  require_command realpath
  resolved_protected="$(realpath -m -- "$protected_path")"
  for candidate_path in "$@"; do
    [[ -n "$candidate_path" ]] || continue
    resolved_candidate="$(realpath -m -- "$candidate_path")"
    [[ "$resolved_protected" != "$resolved_candidate" && "$resolved_protected" != "$resolved_candidate"/* &&
       "$resolved_candidate" != "$resolved_protected"/* ]] ||
      fail "$description must not overlap: $protected_path and $candidate_path"
  done
}

resolve_relative_path_under() {
  local output_name="$1" relative_path="$2" root="$3" relative_key="$4" root_key="$5"
  local resolved_path resolved_root
  require_command realpath
  if ! resolved_path="$(realpath -e -- "$root/$relative_path")"; then
    fail "$relative_key does not exist beneath $root_key: $relative_path"
  fi
  if ! resolved_root="$(realpath -e -- "$root")"; then
    fail "$root_key does not exist: $root"
  fi
  [[ "$resolved_path" == "$resolved_root"/* ]] ||
    fail "$relative_key resolves outside $root_key through a symbolic link"
  printf -v "$output_name" '%s' "$resolved_path"
}

require_regular_file() {
  [[ -f "$1" && ! -L "$1" && -s "$1" ]] || fail "required non-empty regular file not found: $1"
}

verify_sha256() {
  local path="$1" expected="$2" actual
  require_regular_file "$path"
  actual="$(sha256sum -- "$path")"
  actual="${actual%% *}"
  [[ "$actual" == "$expected" ]] || fail "SHA-256 mismatch for: $path"
}

verify_evidence() {
  local path_key="$1" sha_key="$2" evidence_path evidence_sha
  require_clean_absolute_path evidence_path "$path_key"
  require_sha256 evidence_sha "$sha_key"
  verify_sha256 "$evidence_path" "$evidence_sha"
}

verify_kernel_checkout() {
  local checkout="$1" commit="$2" identity_record="$3" actual
  require_command git
  require_regular_file "$identity_record"
  grep -Fx "commit=$commit" -- "$identity_record" >/dev/null || fail "kernel identity record does not match KERNEL_COMMIT_SHA"
  [[ -d "$checkout/.git" && ! -L "$checkout/.git" ]] || fail "kernel checkout is not a local Git checkout"
  actual="$(git_clean -C "$checkout" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || fail "kernel checkout HEAD does not match KERNEL_COMMIT_SHA"
  [[ -z "$(git_clean -C "$checkout" symbolic-ref -q HEAD || true)" ]] || fail "kernel checkout is not detached"
  git_clean -C "$checkout" diff --quiet || fail "kernel checkout has tracked modifications"
  git_clean -C "$checkout" diff --cached --quiet || fail "kernel checkout has staged modifications"
  [[ -z "$(git_clean -C "$checkout" status --porcelain --untracked-files=all --ignored=matching)" ]] || fail "kernel checkout is not clean"
}

git_clean() {
  local git_executable
  require_command git
  git_executable="$(command -v -- git)"
  env -i PATH="$PATH" GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 "$git_executable" "$@"
}

verify_config_record() {
  local config="$1" record="$2" actual
  require_regular_file "$config"
  require_regular_file "$record"
  actual="$(sha256sum -- "$config")"; actual="${actual%% *}"
  grep -Fx "config=$config" -- "$record" >/dev/null || fail "config SHA-256 record names a different config"
  grep -Fx "sha256=$actual" -- "$record" >/dev/null || fail "config SHA-256 record does not match config"
}

verify_configure_record() {
  local record="$1" source_config="$2" merged_config="$3" commit="$4" board_sha="$5" wifi_evidence_sha="$6" camera_evidence_sha="$7"
  local wifi_fragment_sha="$8" camera_fragment_sha="$9" source_actual merged_actual
  require_regular_file "$record"
  require_regular_file "$source_config"
  require_regular_file "$merged_config"
  source_actual="$(sha256sum -- "$source_config")"; source_actual="${source_actual%% *}"
  merged_actual="$(sha256sum -- "$merged_config")"; merged_actual="${merged_actual%% *}"
  grep -Fx "config=$source_config" -- "$record" >/dev/null || fail "configure record names a different source config"
  grep -Fx "source_config_sha256=$source_actual" -- "$record" >/dev/null || fail "configure record does not match source config"
  grep -Fx "kernel_commit=$commit" -- "$record" >/dev/null || fail "configure record does not match KERNEL_COMMIT_SHA"
  grep -Fx "board_evidence_sha256=$board_sha" -- "$record" >/dev/null || fail "configure record does not match board evidence"
  grep -Fx "wifi_evidence_sha256=$wifi_evidence_sha" -- "$record" >/dev/null || fail "configure record does not match Wi-Fi evidence"
  grep -Fx "camera_evidence_sha256=$camera_evidence_sha" -- "$record" >/dev/null || fail "configure record does not match camera evidence"
  grep -Fx "wifi_fragment_sha256=$wifi_fragment_sha" -- "$record" >/dev/null || fail "configure record does not match Wi-Fi fragment"
  grep -Fx "camera_fragment_sha256=$camera_fragment_sha" -- "$record" >/dev/null || fail "configure record does not match camera fragment"
  grep -Fx "merged_config=$merged_config" -- "$record" >/dev/null || fail "configure record names a different merged config"
  grep -Fx "merged_config_sha256=$merged_actual" -- "$record" >/dev/null || fail "configure record does not match merged config"
}

reject_credential_url() {
  local value="$1"
  [[ ! "$value" =~ ://[^/]*@ ]] || fail "URLs with embedded credentials are forbidden"
}

new_output_path() {
  [[ ! -e "$1" && ! -L "$1" ]] || fail "refusing to overwrite existing output: $1"
}

write_text_record() {
  local target="$1"
  shift
  local parent temporary
  parent="$(dirname -- "$target")"
  mkdir -p -- "$parent"
  temporary="$(mktemp "${parent}/.workflow-record.XXXXXX")"
  printf '%s\n' "$@" > "$temporary"
  mv -T -- "$temporary" "$target"
  require_regular_file "$target"
}

script_directory() {
  local directory
  directory="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
  printf '%s' "$directory"
}
