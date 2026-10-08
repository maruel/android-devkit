#!/usr/bin/env bash
# Extract a configuration with source identity and checksum provenance.
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare source_kind archive_sha destination config_sha_record release archive host user port remote_path config_sha checkout config_output_root provenance_path
declare destination_parent provenance_parent config_sha_record_parent archive_parent archive_temporary config_temporary completed output_parent
require_field source_kind CONFIG_SOURCE
[[ "$source_kind" == archive || "$source_kind" == ssh ]] || fail "CONFIG_SOURCE must be archive or ssh"
require_sha256 archive_sha CONFIG_ARCHIVE_SHA256
require_clean_absolute_path checkout KERNEL_CHECKOUT_DIR
require_clean_absolute_path config_output_root CONFIG_OUTPUT_ROOT
require_resolved_path_under destination CONFIG_DESTINATION CONFIG_OUTPUT_ROOT
require_resolved_path_under config_sha_record CONFIG_SHA256_RECORD_PATH CONFIG_OUTPUT_ROOT
require_field release KERNEL_TARGET_RELEASE
require_command sha256sum
require_command gzip
require_command date
if [[ "$source_kind" == archive ]]; then
  require_clean_absolute_path archive CONFIG_ARCHIVE_PATH
  require_regular_file "$archive"
else
  require_resolved_path_under archive CONFIG_ARCHIVE_OUTPUT CONFIG_OUTPUT_ROOT
  require_field host CONFIG_SSH_HOST
  require_field user CONFIG_SSH_USER
  require_field port CONFIG_SSH_PORT
  require_field remote_path CONFIG_SSH_REMOTE_PATH
  [[ "$host" != *'@'* && "$user" != *'@'* && "$port" =~ ^[0-9]{1,5}$ && "$remote_path" == /* ]] ||
    fail "SSH configuration is invalid or contains credentials"
  require_command scp
fi
if [[ "$source_kind" == ssh ]]; then
  require_paths_outside "$checkout" "kernel checkout and generated paths" "$config_output_root" "$archive" "$destination" "$config_sha_record" "${destination}.provenance"
else
  require_paths_outside "$checkout" "kernel checkout and generated paths" "$config_output_root" "$destination" "$config_sha_record" "${destination}.provenance"
fi
require_non_overlapping_paths "configuration outputs" "$archive" "$destination" "$config_sha_record" "${destination}.provenance"
new_output_path "$destination"
new_output_path "${destination}.provenance"
new_output_path "$config_sha_record"
[[ "$source_kind" != ssh ]] || new_output_path "$archive"
provenance_path="${destination}.provenance"
destination_parent="$(dirname -- "$destination")"
provenance_parent="$(dirname -- "$provenance_path")"
config_sha_record_parent="$(dirname -- "$config_sha_record")"
for output_parent in "$destination_parent" "$provenance_parent" "$config_sha_record_parent"; do
  mkdir -p -- "$output_parent"
  [[ -d "$output_parent" && ! -L "$output_parent" ]] || fail "configuration output parent is unsafe: $output_parent"
done
if [[ "$source_kind" == ssh ]]; then
  archive_parent="$(dirname -- "$archive")"
  mkdir -p -- "$archive_parent"
  [[ -d "$archive_parent" && ! -L "$archive_parent" ]] || fail "configuration output parent is unsafe: $archive_parent"
fi
archive_temporary=""
config_temporary=""
completed=false
cleanup() {
  [[ -z "$archive_temporary" ]] || rm -f -- "$archive_temporary"
  [[ -z "$config_temporary" ]] || rm -f -- "$config_temporary"
  if [[ "$completed" != true ]]; then
    [[ "$source_kind" != ssh ]] || rm -f -- "$archive"
    rm -f -- "$destination" "$config_sha_record" "$provenance_path"
  fi
}
trap cleanup EXIT
if [[ "$source_kind" == ssh ]]; then
  archive_temporary="$(mktemp "${archive_parent}/.config-archive.XXXXXX")"
  scp -P "$port" -- "$user@$host:$remote_path" "$archive_temporary"
  verify_sha256 "$archive_temporary" "$archive_sha"
  mv -T -- "$archive_temporary" "$archive"
  archive_temporary=""
  require_regular_file "$archive"
else
  verify_sha256 "$archive" "$archive_sha"
fi
gzip --test -- "$archive" || fail "configuration archive is not a valid gzip stream"
config_temporary="$(mktemp "$(dirname -- "$destination")/.kernel-config.XXXXXX")"
gzip --decompress --stdout -- "$archive" > "$config_temporary"
mv -T -- "$config_temporary" "$destination"
config_temporary=""
require_regular_file "$destination"
config_sha="$(sha256sum -- "$destination")"
config_sha="${config_sha%% *}"
write_text_record "$config_sha_record" "config=$destination" "sha256=$config_sha" "archive_sha256=$archive_sha"
write_text_record "$provenance_path" \
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command=extract-config.sh --manifest" \
  "source=$source_kind" "archive=$archive" "archive_sha256=$archive_sha" \
  "target_release=$release" "config=$destination"
completed=true
trap - EXIT
printf 'extracted kernel configuration: %s\n' "$destination"
