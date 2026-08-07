#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare url release expected_sha destination decompression decompressed checkout artifacts_root
require_field url BASE_IMAGE_URL
reject_credential_url "$url"
require_field release BASE_IMAGE_RELEASE
require_sha256 expected_sha BASE_IMAGE_SHA256
require_clean_absolute_path checkout KERNEL_CHECKOUT_DIR
require_clean_absolute_path artifacts_root ARTIFACTS_ROOT
require_resolved_path_under destination BASE_IMAGE_DESTINATION ARTIFACTS_ROOT
require_field decompression BASE_IMAGE_DECOMPRESS
[[ "$decompression" == none || "$decompression" == xz || "$decompression" == gzip ]] ||
  fail "BASE_IMAGE_DECOMPRESS must be none, xz, or gzip"
decompressed=""
if [[ "$decompression" != none ]]; then
  require_resolved_path_under decompressed BASE_IMAGE_DECOMPRESSED_DESTINATION ARTIFACTS_ROOT
fi
require_paths_outside "$checkout" "kernel checkout and generated paths" "$artifacts_root" "$destination" "$decompressed" "${destination}.sha256"
require_non_overlapping_paths "base image outputs" "$destination" "$decompressed" "${destination}.sha256"
new_output_path "$destination"
new_output_path "${destination}.sha256"
[[ -z "$decompressed" ]] || new_output_path "$decompressed"
require_command curl
require_command sha256sum
require_command date
case "$decompression" in
  xz) require_command xz ;;
  gzip) require_command gzip ;;
esac
destination_parent="$(dirname -- "$destination")"
if [[ "$decompression" != none ]]; then
  decompressed_parent="$(dirname -- "$decompressed")"
fi
mkdir -p -- "$destination_parent"
if [[ "$decompression" != none ]]; then
  mkdir -p -- "$decompressed_parent"
fi
download_temporary="$(mktemp "${destination_parent}/.base-image.XXXXXX")"
decompression_temporary=""
destination_committed=false
decompressed_committed=false
record_committed=false
cleanup() {
  rm -f -- "$download_temporary"
  [[ -z "$decompression_temporary" ]] || rm -f -- "$decompression_temporary"
  if [[ "$record_committed" != true ]]; then
    [[ "$destination_committed" != true ]] || rm -f -- "$destination"
    [[ "$decompressed_committed" != true || -z "$decompressed" ]] || rm -f -- "$decompressed"
    rm -f -- "${destination}.sha256"
  fi
}
trap cleanup EXIT
curl --fail --location --silent --show-error --proto '=https,http,file' --output "$download_temporary" -- "$url"
verify_sha256 "$download_temporary" "$expected_sha"
if [[ "$decompression" == xz ]]; then
  decompression_temporary="$(mktemp "${decompressed_parent}/.base-image-expanded.XXXXXX")"
  xz --decompress --keep --stdout -- "$download_temporary" > "$decompression_temporary"
  mv -T -- "$decompression_temporary" "$decompressed"
  decompression_temporary=""
  decompressed_committed=true
  require_regular_file "$decompressed"
elif [[ "$decompression" == gzip ]]; then
  decompression_temporary="$(mktemp "${decompressed_parent}/.base-image-expanded.XXXXXX")"
  gzip --decompress --stdout -- "$download_temporary" > "$decompression_temporary"
  mv -T -- "$decompression_temporary" "$decompressed"
  decompression_temporary=""
  decompressed_committed=true
  require_regular_file "$decompressed"
fi
if [[ "$decompression" != none ]]; then
  require_regular_file "$decompressed"
fi
mv -T -- "$download_temporary" "$destination"
destination_committed=true
require_regular_file "$destination"
write_text_record "${destination}.sha256" \
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" "command=fetch-base-image.sh --manifest" \
  "release=$release" "url=$url" "sha256=$expected_sha" "downloaded_path=$destination" \
  "decompression=$decompression" "decompressed_path=${decompressed:-none}"
record_committed=true
trap - EXIT
printf 'verified base image: %s\n' "$destination"
