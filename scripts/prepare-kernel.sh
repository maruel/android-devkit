#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=workflow-lib.bash
# shellcheck disable=SC1091
source "$script_dir/workflow-lib.bash"

[[ $# -eq 2 && "$1" == --manifest ]] || usage_manifest
parse_manifest "$2"
declare repo commit release work_root checkout identity_record identity_parent temporary checkout_published
require_field repo KERNEL_REPO_URL
reject_credential_url "$repo"
require_commit_sha commit
require_field release KERNEL_TARGET_RELEASE
require_clean_absolute_path work_root KERNEL_BUILD_ROOT
require_resolved_path_under checkout KERNEL_CHECKOUT_DIR KERNEL_BUILD_ROOT
require_resolved_path_under identity_record KERNEL_IDENTITY_RECORD_PATH KERNEL_BUILD_ROOT
require_non_overlapping_paths "kernel preparation outputs" "$checkout" "$identity_record"
new_output_path "$checkout"
new_output_path "$identity_record"
require_command git
require_command date
identity_parent="$(dirname -- "$identity_record")"
mkdir -p -- "$identity_parent"
[[ -d "$identity_parent" && ! -L "$identity_parent" ]] || fail "kernel identity record parent is unsafe: $identity_parent"
mkdir -p -- "$work_root"
temporary="$(mktemp -d "${work_root}/.kernel-checkout.XXXXXX")"
checkout_published=false
cleanup() {
  [[ -z "$temporary" ]] || rm -rf -- "$temporary"
  [[ "$checkout_published" != true ]] || rm -rf -- "$checkout"
}
trap cleanup EXIT
git_clean init --quiet -- "$temporary"
[[ -d "$temporary/.git" && ! -L "$temporary/.git" ]] || fail "git init did not create a local .git directory"
git_clean -C "$temporary" fetch --no-tags --depth=1 "$repo" "$commit"
actual="$(git_clean -C "$temporary" rev-parse FETCH_HEAD)"
[[ "$actual" == "$commit" ]] || fail "fetched commit differs from KERNEL_COMMIT_SHA"
git_clean -C "$temporary" checkout --quiet --detach "$commit"
[[ "$(git_clean -C "$temporary" symbolic-ref -q HEAD || true)" == "" ]] || fail "kernel checkout is not detached"
mv -T -- "$temporary" "$checkout"
temporary=""
checkout_published=true
write_text_record "$identity_record" \
  "generated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "command=git-fetch-commit-and-checkout-detach" "repository=$repo" "commit=$commit" \
  "target_release=$release" "checkout=$checkout"
trap - EXIT
printf 'prepared detached kernel checkout: %s\n' "$checkout"
