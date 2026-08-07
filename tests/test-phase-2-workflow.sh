#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
temporary="$(mktemp -d)"
readonly temporary
trap 'rm -rf -- "$temporary"' EXIT

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

expect_failure_message() {
  local expected="$1"
  shift
  local output
  if output="$("$@" 2>&1)"; then
    fail "command unexpectedly succeeded: $*"
  fi
  [[ "$output" == *"$expected"* ]] ||
    fail "expected error text '$expected', got: $output"
}

sha() {
  sha256sum -- "$1" | cut -d ' ' -f 1
}

printf 'payload\n' > "$temporary/payload"
payload_sha="$(sha "$temporary/payload")"
mkdir -p -- "$temporary/artifacts"
cat > "$temporary/fetch.manifest" <<EOF
ARTIFACTS_ROOT=$temporary/artifacts
BASE_IMAGE_DECOMPRESS=none
BASE_IMAGE_DESTINATION=$temporary/artifacts/image.bin
BASE_IMAGE_RELEASE=test-release
BASE_IMAGE_SHA256=$payload_sha
BASE_IMAGE_URL=file://$temporary/payload
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
EOF
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary|" "$temporary/fetch.manifest" > "$temporary/fetch-checkout-ancestor.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-checkout-ancestor.manifest"
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary/artifacts/immutable-checkout|" "$temporary/fetch.manifest" > "$temporary/fetch-checkout-descendant.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-checkout-descendant.manifest"
expect_failure_message 'manifest is not a regular file' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/missing.manifest"
cp -- "$temporary/fetch.manifest" "$temporary/invalid.manifest"
printf '%s\n' 'UNEXPECTED_FIELD=value' >> "$temporary/invalid.manifest"
expect_failure_message 'manifest contains unexpected field: UNEXPECTED_FIELD' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/invalid.manifest"
sed '/KERNEL_CHECKOUT_DIR=/d' "$temporary/fetch.manifest" > "$temporary/fetch-missing-checkout.manifest"
expect_failure_message 'manifest is missing required field: KERNEL_CHECKOUT_DIR' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-missing-checkout.manifest"
sed "s|BASE_IMAGE_DESTINATION=.*|BASE_IMAGE_DESTINATION=$temporary/artifacts/hasPLACEHOLDERinside.bin|" \
  "$temporary/fetch.manifest" > "$temporary/placeholder.manifest"
expect_failure_message 'manifest field remains a placeholder: BASE_IMAGE_DESTINATION' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/placeholder.manifest"
wrong_sha="0000000000000000000000000000000000000000000000000000000000000000"
sed "s/$payload_sha/$wrong_sha/" "$temporary/fetch.manifest" > "$temporary/mismatch.manifest"
expect_failure_message 'SHA-256 mismatch' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/mismatch.manifest"
[[ ! -e "$temporary/artifacts/image.bin" ]] || fail "SHA mismatch retained downloaded output"
mkdir -p -- "$temporary/outside-artifacts"
ln -s -- "$temporary/outside-artifacts" "$temporary/artifacts/escaped"
sed "s|BASE_IMAGE_DESTINATION=.*|BASE_IMAGE_DESTINATION=$temporary/artifacts/escaped/image.bin|" \
  "$temporary/fetch.manifest" > "$temporary/symlink-output.manifest"
expect_failure_message 'resolves outside ARTIFACTS_ROOT through a symbolic link' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/symlink-output.manifest"
[[ ! -e "$temporary/outside-artifacts/image.bin" ]] || fail "symlinked output escaped artifacts root"
mkdir -p -- "$temporary/raced-record"
# shellcheck disable=SC2016
expect_failure_message 'cannot overwrite directory' \
  bash -c 'source "$1"; write_text_record "$2" record=value' _ "$repo_root/scripts/workflow-lib.bash" "$temporary/raced-record"
[[ -d "$temporary/raced-record" ]] || fail "record race replaced pre-existing directory"
gzip --stdout -- "$temporary/payload" > "$temporary/payload.gz"
mkdir -p -- "$temporary/fetch-gzip-artifacts"
cat > "$temporary/fetch-gzip.manifest" <<EOF
ARTIFACTS_ROOT=$temporary/fetch-gzip-artifacts
BASE_IMAGE_DECOMPRESS=gzip
BASE_IMAGE_DECOMPRESSED_DESTINATION=$temporary/fetch-gzip-artifacts/nested/image.bin
BASE_IMAGE_DESTINATION=$temporary/fetch-gzip-artifacts/image.bin.gz
BASE_IMAGE_RELEASE=test-release
BASE_IMAGE_SHA256=$(sha "$temporary/payload.gz")
BASE_IMAGE_URL=file://$temporary/payload.gz
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
EOF
sed "s|BASE_IMAGE_DECOMPRESSED_DESTINATION=.*|BASE_IMAGE_DECOMPRESSED_DESTINATION=$temporary/fetch-gzip-artifacts/image.bin.gz|" \
  "$temporary/fetch-gzip.manifest" > "$temporary/fetch-colliding-output.manifest"
expect_failure_message 'base image outputs must not overlap' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-colliding-output.manifest"
sed "s|BASE_IMAGE_DECOMPRESSED_DESTINATION=.*|BASE_IMAGE_DECOMPRESSED_DESTINATION=$temporary/fetch-gzip-artifacts/image.bin.gz/expanded|" \
  "$temporary/fetch-gzip.manifest" > "$temporary/fetch-nested-output.manifest"
expect_failure_message 'base image outputs must not overlap' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-nested-output.manifest"
[[ ! -e "$temporary/fetch-gzip-artifacts/image.bin.gz" && ! -e "$temporary/fetch-gzip-artifacts/image.bin.gz/expanded" ]] ||
  fail "overlapping base-image outputs were created"
"$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-gzip.manifest" >/dev/null
cmp -- "$temporary/payload" "$temporary/fetch-gzip-artifacts/nested/image.bin" ||
  fail "gzip base-image decompression changed content"
printf 'not gzip\n' > "$temporary/not-gzip"
mkdir -p -- "$temporary/fetch-failure-artifacts"
cat > "$temporary/fetch-failure.manifest" <<EOF
ARTIFACTS_ROOT=$temporary/fetch-failure-artifacts
BASE_IMAGE_DECOMPRESS=gzip
BASE_IMAGE_DECOMPRESSED_DESTINATION=$temporary/fetch-failure-artifacts/image.bin
BASE_IMAGE_DESTINATION=$temporary/fetch-failure-artifacts/image.bin.gz
BASE_IMAGE_RELEASE=test-release
BASE_IMAGE_SHA256=$(sha "$temporary/not-gzip")
BASE_IMAGE_URL=file://$temporary/not-gzip
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
EOF
expect_failure_message 'not in gzip format' \
  "$repo_root/scripts/fetch-base-image.sh" --manifest "$temporary/fetch-failure.manifest"
[[ ! -e "$temporary/fetch-failure-artifacts/image.bin.gz" ]] || fail "failed decompression retained download"
[[ ! -e "$temporary/fetch-failure-artifacts/image.bin" ]] || fail "failed decompression retained expanded image"
[[ ! -e "$temporary/fetch-failure-artifacts/image.bin.gz.sha256" ]] || fail "failed decompression retained record"

printf 'kernel config\n' > "$temporary/config-source"
gzip --stdout -- "$temporary/config-source" > "$temporary/config.gz"
mkdir -p -- "$temporary/config-output"
cat > "$temporary/extract.manifest" <<EOF
CONFIG_ARCHIVE_PATH=$temporary/config.gz
CONFIG_ARCHIVE_SHA256=$(sha "$temporary/config.gz")
CONFIG_DESTINATION=$temporary/config-output/.config
CONFIG_OUTPUT_ROOT=$temporary/config-output
CONFIG_SHA256_RECORD_PATH=$temporary/config-output/.config.sha256
CONFIG_SOURCE=archive
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
KERNEL_TARGET_RELEASE=test-release
EOF
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary|" "$temporary/extract.manifest" > "$temporary/extract-checkout-ancestor.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-checkout-ancestor.manifest"
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary/config-output/immutable-checkout|" "$temporary/extract.manifest" > "$temporary/extract-checkout-descendant.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-checkout-descendant.manifest"
sed '/KERNEL_CHECKOUT_DIR=/d' "$temporary/extract.manifest" > "$temporary/extract-missing-checkout.manifest"
expect_failure_message 'manifest is missing required field: KERNEL_CHECKOUT_DIR' \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-missing-checkout.manifest"
sed "s|CONFIG_SHA256_RECORD_PATH=.*|CONFIG_SHA256_RECORD_PATH=$temporary/config-output/.config|" \
  "$temporary/extract.manifest" > "$temporary/extract-colliding-output.manifest"
expect_failure_message 'configuration outputs must not overlap' \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-colliding-output.manifest"
mkdir -p -- "$temporary/extract-ssh-output"
cat > "$temporary/extract-ssh-overlap.manifest" <<EOF
CONFIG_ARCHIVE_OUTPUT=$temporary/extract-ssh-output/.config/archive.gz
CONFIG_ARCHIVE_SHA256=$(sha "$temporary/config.gz")
CONFIG_DESTINATION=$temporary/extract-ssh-output/.config
CONFIG_OUTPUT_ROOT=$temporary/extract-ssh-output
CONFIG_SHA256_RECORD_PATH=$temporary/extract-ssh-output/.config.sha256
CONFIG_SOURCE=ssh
CONFIG_SSH_HOST=example.test
CONFIG_SSH_PORT=22
CONFIG_SSH_REMOTE_PATH=/proc/config.gz
CONFIG_SSH_USER=test
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
KERNEL_TARGET_RELEASE=test-release
EOF
expect_failure_message 'configuration outputs must not overlap' \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-ssh-overlap.manifest"
[[ ! -e "$temporary/extract-ssh-output/.config" && ! -e "$temporary/extract-ssh-output/.config.sha256" ]] ||
  fail "overlapping configuration outputs were created"
mkdir -p -- "$temporary/fake-extract-bin"
cat > "$temporary/fake-extract-bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${!#}" == "${FAIL_MV_TARGET:-}" ]]; then
  printf 'forced move failure\n' >&2
  exit 9
fi
exec /bin/mv "$@"
EOF
chmod +x "$temporary/fake-extract-bin/mv"
mkdir -p -- "$temporary/extract-rollback-output"
cat > "$temporary/extract-rollback.manifest" <<EOF
CONFIG_ARCHIVE_PATH=$temporary/config.gz
CONFIG_ARCHIVE_SHA256=$(sha "$temporary/config.gz")
CONFIG_DESTINATION=$temporary/extract-rollback-output/.config
CONFIG_OUTPUT_ROOT=$temporary/extract-rollback-output
CONFIG_SHA256_RECORD_PATH=$temporary/extract-rollback-output/.config.sha256
CONFIG_SOURCE=archive
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
KERNEL_TARGET_RELEASE=test-release
EOF
expect_failure_message 'forced move failure' \
  env FAIL_MV_TARGET="$temporary/extract-rollback-output/.config.provenance" PATH="$temporary/fake-extract-bin:$PATH" \
  "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-rollback.manifest"
[[ ! -e "$temporary/extract-rollback-output/.config" && ! -e "$temporary/extract-rollback-output/.config.sha256" &&
   ! -e "$temporary/extract-rollback-output/.config.provenance" ]] || fail "failed config provenance retained output"
cat > "$temporary/fake-extract-bin/scp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cp -- "${SCP_SOURCE:?}" "${!#}"
EOF
chmod +x "$temporary/fake-extract-bin/scp"
mkdir -p -- "$temporary/extract-ssh-rollback-output"
cat > "$temporary/extract-ssh-rollback.manifest" <<EOF
CONFIG_ARCHIVE_OUTPUT=$temporary/extract-ssh-rollback-output/config.gz
CONFIG_ARCHIVE_SHA256=$(sha "$temporary/config.gz")
CONFIG_DESTINATION=$temporary/extract-ssh-rollback-output/.config
CONFIG_OUTPUT_ROOT=$temporary/extract-ssh-rollback-output
CONFIG_SHA256_RECORD_PATH=$temporary/extract-ssh-rollback-output/.config.sha256
CONFIG_SOURCE=ssh
CONFIG_SSH_HOST=example.test
CONFIG_SSH_PORT=22
CONFIG_SSH_REMOTE_PATH=/proc/config.gz
CONFIG_SSH_USER=test
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
KERNEL_TARGET_RELEASE=test-release
EOF
expect_failure_message 'forced move failure' \
  env SCP_SOURCE="$temporary/config.gz" FAIL_MV_TARGET="$temporary/extract-ssh-rollback-output/.config.provenance" \
  PATH="$temporary/fake-extract-bin:$PATH" "$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract-ssh-rollback.manifest"
[[ ! -e "$temporary/extract-ssh-rollback-output/config.gz" && ! -e "$temporary/extract-ssh-rollback-output/.config" &&
   ! -e "$temporary/extract-ssh-rollback-output/.config.sha256" && ! -e "$temporary/extract-ssh-rollback-output/.config.provenance" ]] ||
  fail "failed SSH config provenance retained output"
"$repo_root/scripts/extract-config.sh" --manifest "$temporary/extract.manifest" >/dev/null
cmp -- "$temporary/config-source" "$temporary/config-output/.config" || fail "config extraction changed content"
grep -Fx "sha256=$(sha "$temporary/config-output/.config")" "$temporary/config-output/.config.sha256" >/dev/null || fail "config SHA-256 record missing"

git init --quiet "$temporary/kernel-origin"
git -C "$temporary/kernel-origin" config user.email test@example.invalid
git -C "$temporary/kernel-origin" config user.name Test
printf 'kernel\n' > "$temporary/kernel-origin/README"
git -C "$temporary/kernel-origin" add README
git -C "$temporary/kernel-origin" commit --quiet -m test
commit="$(git -C "$temporary/kernel-origin" rev-parse HEAD)"
mkdir -p -- "$temporary/kernel-work"
cat > "$temporary/kernel.manifest" <<EOF
KERNEL_BUILD_ROOT=$temporary/kernel-work
KERNEL_CHECKOUT_DIR=$temporary/kernel-work/source
KERNEL_COMMIT_SHA=$commit
KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel-work/kernel.identity
KERNEL_REPO_URL=file://$temporary/kernel-origin
KERNEL_TARGET_RELEASE=test-release
EOF
sed "s|KERNEL_IDENTITY_RECORD_PATH=.*|KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel-work/source/kernel.identity|" \
  "$temporary/kernel.manifest" > "$temporary/kernel-overlapping-output.manifest"
expect_failure_message 'kernel preparation outputs must not overlap' \
  "$repo_root/scripts/prepare-kernel.sh" --manifest "$temporary/kernel-overlapping-output.manifest"
ln -s -- "$temporary/kernel-work" "$temporary/kernel-work/identity-parent-link"
sed "s|KERNEL_IDENTITY_RECORD_PATH=.*|KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel-work/identity-parent-link/kernel.identity|" \
  "$temporary/kernel.manifest" > "$temporary/kernel-identity-parent-link.manifest"
expect_failure_message 'kernel identity record parent is unsafe' \
  "$repo_root/scripts/prepare-kernel.sh" --manifest "$temporary/kernel-identity-parent-link.manifest"
[[ ! -e "$temporary/kernel-work/source" ]] || fail "identity parent preflight created checkout"
sed "s|KERNEL_IDENTITY_RECORD_PATH=.*|KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel-work/kernel-failing.identity|" \
  "$temporary/kernel.manifest" > "$temporary/kernel-identity-write-failure.manifest"
expect_failure_message 'forced move failure' \
  env FAIL_MV_TARGET="$temporary/kernel-work/kernel-failing.identity" PATH="$temporary/fake-extract-bin:$PATH" \
  "$repo_root/scripts/prepare-kernel.sh" --manifest "$temporary/kernel-identity-write-failure.manifest"
[[ ! -e "$temporary/kernel-work/source" && ! -e "$temporary/kernel-work/kernel-failing.identity" ]] ||
  fail "identity publication failure retained prepared checkout"
env GIT_DIR="$temporary/hostile-git-dir" GIT_WORK_TREE="$temporary/hostile-work-tree" \
  GIT_INDEX_FILE="$temporary/hostile-index" GIT_OBJECT_DIRECTORY="$temporary/hostile-objects" GIT_CONFIG_NOSYSTEM=0 \
  "$repo_root/scripts/prepare-kernel.sh" --manifest "$temporary/kernel.manifest" >/dev/null
[[ "$(git -C "$temporary/kernel-work/source" rev-parse HEAD)" == "$commit" ]] || fail "wrong kernel commit"
[[ -z "$(git -C "$temporary/kernel-work/source" symbolic-ref -q HEAD || true)" ]] || fail "kernel checkout is not detached"
[[ -d "$temporary/kernel-work/source/.git" && ! -L "$temporary/kernel-work/source/.git" ]] || fail "kernel checkout lacks a local .git directory"

checkout="$temporary/kernel-tree"
build_dir="$temporary/kernel-build"
mkdir -p -- "$checkout/scripts/kconfig" "$checkout/drivers/wifi" "$checkout/drivers/camera"
printf 'all:\n' > "$checkout/Makefile"
printf '*.stale\n' > "$checkout/.gitignore"
cat > "$checkout/scripts/kconfig/merge_config.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ "$1" == -* ]]; do
  if [[ "$1" == -O ]]; then shift 2; else shift; fi
done
config="$1"
shift
for fragment in "$@"; do
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^CONFIG_[A-Za-z0-9_]+= || "$line" =~ ^\#\ CONFIG_[A-Za-z0-9_]+\ is\ not\ set$ ]] || continue
    [[ "$line" == "${DROP_SYMBOL:-}="* || "$line" == "# ${DROP_SYMBOL:-} is not set" ]] && continue
    printf '%s\n' "$line" >> "$config"
  done < "$fragment"
done
EOF
chmod +x "$checkout/scripts/kconfig/merge_config.sh"
outside_module_dir="$temporary/outside-module-dir"
mkdir -p -- "$outside_module_dir"
ln -s -- "$outside_module_dir" "$checkout/drivers/escaped-wifi"
git init --quiet "$checkout"
git -C "$checkout" config user.email test@example.invalid
git -C "$checkout" config user.name Test
git -C "$checkout" add .
git -C "$checkout" commit --quiet -m kernel
checkout_commit="$(git -C "$checkout" rev-parse HEAD)"
git -C "$checkout" checkout --quiet --detach "$checkout_commit"
mkdir -p -- "$temporary/fake-bin" "$temporary/kernel-artifacts"
cat > "$temporary/fake-bin/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${MAKE_LOG:?}"
printf '%s\n' "$*" >> "$MAKE_LOG"
checkout=""
build=""
module_dir=""
target="${!#}"
while (($# > 0)); do
  case "$1" in
    -C) checkout="$2"; shift 2 ;;
    O=*) build="${1#O=}"; shift ;;
    M=*) module_dir="${1#M=}"; shift ;;
    *) shift ;;
  esac
done
if [[ "$target" == kernelrelease ]]; then printf 'test-release\n'; exit 0; fi
if [[ "$target" == modules ]]; then
  mkdir -p -- "$checkout/$module_dir"
  case "$module_dir" in
    drivers/wifi) printf 'wifi\n' > "$checkout/$module_dir/brcmfmac.ko"; printf 'util\n' > "$checkout/$module_dir/brcmutil.ko" ;;
    drivers/camera)
      [[ "${FAIL_CAMERA_OUTPUT:-false}" == true ]] || printf 'camera\n' > "$checkout/$module_dir/ov5640.ko"
      ;;
    *) exit 7 ;;
  esac
fi
EOF
chmod +x "$temporary/fake-bin/make"
config_output_root="$temporary/kernel-config-output"
mkdir -p -- "$config_output_root"
printf 'CONFIG_BASE=y\n' > "$config_output_root/base.config"
printf 'config=%s\nsha256=%s\n' "$config_output_root/base.config" "$(sha "$config_output_root/base.config")" > "$config_output_root/base.config.sha256"
printf 'CONFIG_WIFI_TEST=y\n# CONFIG_WIFI_DISABLED is not set\n' > "$temporary/wifi.fragment"
printf 'CONFIG_CAMERA_TEST=m\n' > "$temporary/camera.fragment"
printf 'board evidence\n' > "$temporary/board.evidence"
printf 'wifi evidence\n' > "$temporary/wifi.evidence"
printf 'camera evidence\n' > "$temporary/camera.evidence"
cat > "$temporary/configure.manifest" <<EOF
ARCH=arm
ARTIFACTS_ROOT=$temporary/kernel-artifacts
BOARD_EVIDENCE_PATH=$temporary/board.evidence
BOARD_EVIDENCE_SHA256=$(sha "$temporary/board.evidence")
CAMERA_EVIDENCE_PATH=$temporary/camera.evidence
CAMERA_EVIDENCE_SHA256=$(sha "$temporary/camera.evidence")
CAMERA_KCONFIG_FRAGMENT=$temporary/camera.fragment
CAMERA_KCONFIG_FRAGMENT_SHA256=$(sha "$temporary/camera.fragment")
CONFIG_DESTINATION=$config_output_root/base.config
CONFIG_OUTPUT_ROOT=$config_output_root
CONFIG_SHA256_RECORD_PATH=$config_output_root/base.config.sha256
CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure.record
CROSS_COMPILE=arm-test-
KERNEL_BUILD_DIR=$build_dir
KERNEL_BUILD_ROOT=$temporary
KERNEL_CHECKOUT_DIR=$checkout
KERNEL_COMMIT_SHA=$checkout_commit
KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel.identity
KERNEL_TARGET_RELEASE=test-release
WIFI_KCONFIG_FRAGMENT=$temporary/wifi.fragment
WIFI_KCONFIG_FRAGMENT_SHA256=$(sha "$temporary/wifi.fragment")
WIFI_EVIDENCE_PATH=$temporary/wifi.evidence
WIFI_EVIDENCE_SHA256=$(sha "$temporary/wifi.evidence")
EOF
printf 'commit=%s\n' "$checkout_commit" > "$temporary/kernel.identity"
sed "s|ARTIFACTS_ROOT=.*|ARTIFACTS_ROOT=$checkout|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$checkout/configure.record|" \
  "$temporary/configure.manifest" > "$temporary/configure-artifacts-in-checkout.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure-artifacts-in-checkout.manifest"
sed "s|KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$temporary/kernel-artifacts/kernel-build-overlap|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/kernel-build-overlap/configure.record|" \
  "$temporary/configure.manifest" > "$temporary/configure-overlapping-output.manifest"
expect_failure_message 'kernel configuration outputs must not overlap' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure-overlapping-output.manifest"
printf 'modified kernel source\n' >> "$checkout/Makefile"
sed "s|KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$temporary/kernel-build-hostile|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure-hostile.record|" \
  "$temporary/configure.manifest" > "$temporary/configure-hostile-checkout.manifest"
expect_failure_message 'kernel checkout has tracked modifications' \
  env GIT_DIR="$temporary/hostile-git-dir" GIT_WORK_TREE="$temporary/hostile-work-tree" GIT_INDEX_FILE="$temporary/hostile-index" \
  GIT_OBJECT_DIRECTORY="$temporary/hostile-objects" MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure-hostile-checkout.manifest"
printf 'all:\n' > "$checkout/Makefile"
MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure.manifest" >/dev/null
grep -F ' prepare' "$temporary/make.log" >/dev/null || fail "configure did not run make prepare"
grep -F ' modules_prepare' "$temporary/make.log" >/dev/null || fail "configure did not run make modules_prepare"
grep -Fx 'CONFIG_WIFI_TEST=y' "$build_dir/.config" >/dev/null || fail "Wi-Fi fragment was not retained"
grep -Fx '# CONFIG_WIFI_DISABLED is not set' "$build_dir/.config" >/dev/null || fail "unset Wi-Fi fragment was not retained"
grep -Fx 'CONFIG_CAMERA_TEST=m' "$build_dir/.config" >/dev/null || fail "camera fragment was not retained"
grep -Fx "kernel_commit=$checkout_commit" "$temporary/kernel-artifacts/configure.record" >/dev/null || fail "configure record did not bind kernel commit"
grep -Fx "merged_config_sha256=$(sha "$build_dir/.config")" "$temporary/kernel-artifacts/configure.record" >/dev/null || fail "configure record did not bind merged config"
expect_failure_message "refusing to overwrite existing output: $build_dir/.config" \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure.manifest"
mkdir -p -- "$temporary/kernel-artifacts"
printf 'existing provenance\n' > "$temporary/kernel-artifacts/configure-existing.record"
sed "s|KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$temporary/kernel-build-record|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure-existing.record|" \
  "$temporary/configure.manifest" > "$temporary/configure-existing-record.manifest"
expect_failure_message "refusing to overwrite existing output: $temporary/kernel-artifacts/configure-existing.record" \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure-existing-record.manifest"
printf 'CONFIG_DROPPED=y\n' > "$temporary/dropped.fragment"
sed "s|WIFI_KCONFIG_FRAGMENT=.*|WIFI_KCONFIG_FRAGMENT=$temporary/dropped.fragment|; s|WIFI_KCONFIG_FRAGMENT_SHA256=.*|WIFI_KCONFIG_FRAGMENT_SHA256=$(sha "$temporary/dropped.fragment")|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure-dropped.record|; s|KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$temporary/kernel-build-dropped|" \
  "$temporary/configure.manifest" > "$temporary/configure-dropped.manifest"
expect_failure_message 'fragment symbol was dropped or changed by configuration: CONFIG_DROPPED' \
  env DROP_SYMBOL=CONFIG_DROPPED MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/configure-kernel.sh" --manifest "$temporary/configure-dropped.manifest"

cat > "$temporary/modules.manifest" <<EOF
ARCH=arm
ARTIFACTS_ROOT=$temporary/kernel-artifacts
BOARD_EVIDENCE_PATH=$temporary/board.evidence
BOARD_EVIDENCE_SHA256=$(sha "$temporary/board.evidence")
CAMERA_EVIDENCE_PATH=$temporary/camera.evidence
CAMERA_EVIDENCE_SHA256=$(sha "$temporary/camera.evidence")
CAMERA_KCONFIG_FRAGMENT=$temporary/camera.fragment
CAMERA_KCONFIG_FRAGMENT_SHA256=$(sha "$temporary/camera.fragment")
CAMERA_MODULE_DIR=drivers/camera
CAMERA_MODULE_KOS=ov5640.ko
CROSS_COMPILE=arm-test-
KERNEL_BUILD_DIR=$build_dir
KERNEL_BUILD_ROOT=$temporary
KERNEL_CHECKOUT_DIR=$checkout
KERNEL_COMMIT_SHA=$checkout_commit
KERNEL_IDENTITY_RECORD_PATH=$temporary/kernel.identity
KERNEL_TARGET_RELEASE=test-release
MODULE_PUBLICATION_DIR=$temporary/kernel-artifacts/modules
CONFIG_OUTPUT_ROOT=$config_output_root
CONFIG_SHA256_RECORD_PATH=$config_output_root/base.config.sha256
CONFIG_DESTINATION=$config_output_root/base.config
CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure.record
WIFI_EVIDENCE_PATH=$temporary/wifi.evidence
WIFI_EVIDENCE_SHA256=$(sha "$temporary/wifi.evidence")
WIFI_KCONFIG_FRAGMENT=$temporary/wifi.fragment
WIFI_KCONFIG_FRAGMENT_SHA256=$(sha "$temporary/wifi.fragment")
WIFI_MODULE_DIR=drivers/wifi
WIFI_MODULE_KOS=brcmfmac.ko,brcmutil.ko
EOF
sed "s|ARTIFACTS_ROOT=.*|ARTIFACTS_ROOT=$checkout/artifacts|; s|CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$checkout/artifacts/configure.record|; s|MODULE_PUBLICATION_DIR=.*|MODULE_PUBLICATION_DIR=$checkout/artifacts/modules|" \
  "$temporary/modules.manifest" > "$temporary/modules-artifacts-in-checkout.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-artifacts-in-checkout.manifest"
sed "s|KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$temporary/kernel-artifacts/modules|; s|MODULE_PUBLICATION_DIR=.*|MODULE_PUBLICATION_DIR=$temporary/kernel-artifacts/modules/published|" \
  "$temporary/modules.manifest" > "$temporary/modules-overlapping-output.manifest"
expect_failure_message 'module outputs must not overlap' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-overlapping-output.manifest"
printf 'modified kernel source\n' >> "$checkout/Makefile"
expect_failure_message 'kernel checkout has tracked modifications' \
  env GIT_DIR="$temporary/hostile-git-dir" GIT_WORK_TREE="$temporary/hostile-work-tree" GIT_INDEX_FILE="$temporary/hostile-index" \
  GIT_OBJECT_DIRECTORY="$temporary/hostile-objects" MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules.manifest"
printf 'all:\n' > "$checkout/Makefile"
sed '/WIFI_MODULE_DIR=/d' "$temporary/modules.manifest" > "$temporary/modules-missing-wifi.manifest"
expect_failure_message 'manifest is missing required field: WIFI_MODULE_DIR' \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-missing-wifi.manifest"
sed 's|WIFI_MODULE_DIR=.*|WIFI_MODULE_DIR=PLACEHOLDERwifi|' "$temporary/modules.manifest" > "$temporary/modules-placeholder-wifi.manifest"
expect_failure_message 'manifest field remains a placeholder: WIFI_MODULE_DIR' \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-placeholder-wifi.manifest"
sed '/CAMERA_MODULE_DIR=/d' "$temporary/modules.manifest" > "$temporary/modules-missing-camera.manifest"
expect_failure_message 'manifest is missing required field: CAMERA_MODULE_DIR' \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-missing-camera.manifest"
sed 's|CAMERA_MODULE_DIR=.*|CAMERA_MODULE_DIR=PLACEHOLDERcamera|' "$temporary/modules.manifest" > "$temporary/modules-placeholder-camera.manifest"
expect_failure_message 'manifest field remains a placeholder: CAMERA_MODULE_DIR' \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-placeholder-camera.manifest"
: > "$temporary/make.log"
sed 's|WIFI_MODULE_KOS=.*|WIFI_MODULE_KOS=brcmfmac.ko,brcmfmac.ko|' "$temporary/modules.manifest" > "$temporary/modules-duplicate-wifi.manifest"
expect_failure_message 'WIFI_MODULE_KOS contains a duplicate module: brcmfmac.ko' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-duplicate-wifi.manifest"
sed 's|CAMERA_MODULE_KOS=.*|CAMERA_MODULE_KOS=brcmfmac.ko|' "$temporary/modules.manifest" > "$temporary/modules-duplicate-output.manifest"
expect_failure_message 'Wi-Fi and camera module output names must be distinct: brcmfmac.ko' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-duplicate-output.manifest"
[[ ! -e "$temporary/kernel-artifacts/modules" ]] || fail "duplicate module declaration created publication output"
[[ ! -s "$temporary/make.log" ]] || fail "duplicate module declaration reached make"
cp -- "$temporary/kernel-artifacts/configure.record" "$temporary/kernel-artifacts/configure-tampered.record"
sed -i 's/^merged_config_sha256=.*/merged_config_sha256=0000000000000000000000000000000000000000000000000000000000000000/' \
  "$temporary/kernel-artifacts/configure-tampered.record"
sed 's|^CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH='"$temporary"'/kernel-artifacts/configure-tampered.record|' \
  "$temporary/modules.manifest" > "$temporary/modules-tampered-configure-record.manifest"
expect_failure_message 'configure record does not match merged config' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-tampered-configure-record.manifest"
printf 'CONFIG_SOURCE_CHANGED=y\n' >> "$config_output_root/base.config"
printf 'config=%s\nsha256=%s\n' "$config_output_root/base.config" "$(sha "$config_output_root/base.config")" > "$config_output_root/base.config.sha256"
expect_failure_message 'configure record does not match source config' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules.manifest"
printf 'CONFIG_BASE=y\n' > "$config_output_root/base.config"
printf 'config=%s\nsha256=%s\n' "$config_output_root/base.config" "$(sha "$config_output_root/base.config")" > "$config_output_root/base.config.sha256"
printf 'ignored stale artifact\n' > "$checkout/ignored.stale"
expect_failure_message 'kernel checkout is not clean' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules.manifest"
rm -- "$checkout/ignored.stale"
sed 's|WIFI_MODULE_DIR=.*|WIFI_MODULE_DIR=drivers/escaped-wifi|' "$temporary/modules.manifest" > "$temporary/modules-escaped-wifi.manifest"
expect_failure_message 'WIFI_MODULE_DIR resolves outside KERNEL_CHECKOUT_DIR through a symbolic link' \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-escaped-wifi.manifest"
failure_root="$temporary/module-failure-root"
failure_checkout="$failure_root/kernel-tree"
failure_build_dir="$failure_root/kernel-build"
mkdir -p -- "$failure_root" "$failure_build_dir"
cp -a -- "$checkout/." "$failure_checkout"
cp -- "$build_dir/.config" "$failure_build_dir/.config"
cp -- "$temporary/kernel.identity" "$failure_root/kernel.identity"
cp -- "$temporary/kernel-artifacts/configure.record" "$temporary/kernel-artifacts/configure-failure.record"
sed -i "s|^merged_config=.*|merged_config=$failure_build_dir/.config|" "$temporary/kernel-artifacts/configure-failure.record"
sed "s|^KERNEL_BUILD_DIR=.*|KERNEL_BUILD_DIR=$failure_build_dir|; s|^KERNEL_BUILD_ROOT=.*|KERNEL_BUILD_ROOT=$failure_root|; s|^KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$failure_checkout|; s|^KERNEL_IDENTITY_RECORD_PATH=.*|KERNEL_IDENTITY_RECORD_PATH=$failure_root/kernel.identity|; s|^CONFIGURE_RECORD_PATH=.*|CONFIGURE_RECORD_PATH=$temporary/kernel-artifacts/configure-failure.record|; s|^MODULE_PUBLICATION_DIR=.*|MODULE_PUBLICATION_DIR=$temporary/kernel-artifacts/modules-failed|" \
  "$temporary/modules.manifest" > "$temporary/modules-late-failure.manifest"
expect_failure_message "required non-empty regular file not found: $failure_root/module-source-stage/drivers/camera/ov5640.ko" \
  env FAIL_CAMERA_OUTPUT=true MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules-late-failure.manifest"
grep -F 'M=drivers/wifi modules' "$temporary/make.log" >/dev/null || fail "late module failure did not build the Wi-Fi module first"
[[ ! -e "$failure_root/module-source-stage" ]] || fail "late module failure retained source staging"
[[ ! -e "$temporary/kernel-artifacts/modules-failed" ]] || fail "late module failure retained publication output"
[[ ! -e "$temporary/kernel-artifacts/modules-failed/modules.record" ]] || fail "late module failure retained publication record"
MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules.manifest" >/dev/null
[[ -f "$temporary/kernel-artifacts/modules/wifi/brcmfmac.ko" ]] || fail "brcmfmac was not exported"
[[ -f "$temporary/kernel-artifacts/modules/wifi/brcmutil.ko" ]] || fail "brcmutil was not exported"
[[ -f "$temporary/kernel-artifacts/modules/camera/ov5640.ko" ]] || fail "camera module was not exported"
grep -Fx "kernel_commit=$checkout_commit" "$temporary/kernel-artifacts/modules/modules.record" >/dev/null || fail "module record did not bind kernel commit"
grep -Fx "source_config_sha256=$(sha "$config_output_root/base.config")" "$temporary/kernel-artifacts/modules/modules.record" >/dev/null || fail "module record did not bind source config"
grep -Fx "merged_config_sha256=$(sha "$build_dir/.config")" "$temporary/kernel-artifacts/modules/modules.record" >/dev/null || fail "module record did not bind merged config"
[[ -f "$temporary/module-source-stage/drivers/wifi/brcmfmac.ko" ]] || fail "Wi-Fi module was not built in staged source"
[[ ! -e "$checkout/drivers/wifi/brcmfmac.ko" && ! -e "$checkout/drivers/wifi/brcmutil.ko" && ! -e "$checkout/drivers/camera/ov5640.ko" ]] ||
  fail "module build modified immutable kernel checkout"
expect_failure_message "refusing to overwrite existing output: $temporary/kernel-artifacts/modules" \
  env MAKE_LOG="$temporary/make.log" PATH="$temporary/fake-bin:$PATH" \
  "$repo_root/scripts/build-modules.sh" --manifest "$temporary/modules.manifest"

printf 'raw image\n' > "$temporary/raw.img"
printf 'spl\n' > "$temporary/spl.bin"
printf 'uboot\n' > "$temporary/u-boot.imx"
printf 'uuu script\n' > "$temporary/flash.uuu"
printf 'boot evidence\n' > "$temporary/boot.evidence"
cat > "$temporary/bundle.manifest.input" <<EOF
ARTIFACTS_ROOT=$temporary/artifacts
BOARD_EVIDENCE_PATH=$temporary/board.evidence
BOARD_EVIDENCE_SHA256=$(sha "$temporary/board.evidence")
BOOT_EVIDENCE_PATH=$temporary/boot.evidence
BOOT_EVIDENCE_SHA256=$(sha "$temporary/boot.evidence")
BUNDLE_DIR=$temporary/artifacts/bundle
BUNDLE_RAW_IMAGE_NAME=image.raw
BUNDLE_SPL_NAME=spl.bin
BUNDLE_UBOOT_NAME=u-boot.imx
BUNDLE_UUU_SCRIPT_NAME=flash.uuu
FLASH_EXPECTED_SDP_ID=imx7d-sdp-15a2:0076
RAW_IMAGE_PATH=$temporary/raw.img
RAW_IMAGE_SHA256=$(sha "$temporary/raw.img")
SPL_PATH=$temporary/spl.bin
SPL_SHA256=$(sha "$temporary/spl.bin")
UBOOT_PATH=$temporary/u-boot.imx
UBOOT_SHA256=$(sha "$temporary/u-boot.imx")
UUU_SCRIPT_PATH=$temporary/flash.uuu
UUU_SCRIPT_SHA256=$(sha "$temporary/flash.uuu")
KERNEL_CHECKOUT_DIR=$temporary/immutable-checkout
EOF
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary|" "$temporary/bundle.manifest.input" > "$temporary/bundle-checkout-ancestor.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-checkout-ancestor.manifest"
sed "s|KERNEL_CHECKOUT_DIR=.*|KERNEL_CHECKOUT_DIR=$temporary/artifacts/immutable-checkout|" "$temporary/bundle.manifest.input" > "$temporary/bundle-checkout-descendant.manifest"
expect_failure_message 'kernel checkout and generated paths must not overlap' \
  "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-checkout-descendant.manifest"
sed '/KERNEL_CHECKOUT_DIR=/d' "$temporary/bundle.manifest.input" > "$temporary/bundle-missing-checkout.manifest"
expect_failure_message 'manifest is missing required field: KERNEL_CHECKOUT_DIR' \
  "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-missing-checkout.manifest"
for empty_field in RAW_IMAGE SPL UBOOT; do
  empty_asset="$temporary/empty-${empty_field,,}"
  : > "$empty_asset"
  sed "s|^${empty_field}_PATH=.*|${empty_field}_PATH=$empty_asset|; s|^${empty_field}_SHA256=.*|${empty_field}_SHA256=$(sha "$empty_asset")|" \
    "$temporary/bundle.manifest.input" > "$temporary/bundle-empty-${empty_field}.manifest"
  expect_failure_message "required non-empty regular file not found: $empty_asset" \
    "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-empty-${empty_field}.manifest"
done
for bundle_name_field in BUNDLE_RAW_IMAGE_NAME BUNDLE_SPL_NAME BUNDLE_UBOOT_NAME BUNDLE_UUU_SCRIPT_NAME; do
  sed "s|^$bundle_name_field=.*|$bundle_name_field=PLACEHOLDERname|" "$temporary/bundle.manifest.input" > "$temporary/bundle-$bundle_name_field.manifest"
  expect_failure_message "manifest field remains a placeholder: $bundle_name_field" \
    "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-$bundle_name_field.manifest"
  sed "/^$bundle_name_field=/d" "$temporary/bundle.manifest.input" > "$temporary/bundle-missing-$bundle_name_field.manifest"
  expect_failure_message "manifest is missing required field: $bundle_name_field" \
    "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-missing-$bundle_name_field.manifest"
done
sed 's|BUNDLE_UUU_SCRIPT_NAME=.*|BUNDLE_UUU_SCRIPT_NAME=bundle.manifest|' "$temporary/bundle.manifest.input" > "$temporary/bundle-reserved-name.manifest"
expect_failure_message 'bundle payload filename is reserved for bundle metadata: bundle.manifest' \
  "$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle-reserved-name.manifest"
"$repo_root/scripts/assemble-flash-bundle.sh" --manifest "$temporary/bundle.manifest.input" >/dev/null
[[ -f "$temporary/artifacts/bundle/bundle.manifest" ]] || fail "bundle manifest missing"
[[ ! -L "$temporary/artifacts/bundle/image.raw" ]] || fail "bundle must copy, not link, image assets"
grep -Fx "BOARD_EVIDENCE_PATH=$temporary/board.evidence" "$temporary/artifacts/bundle/bundle.manifest" >/dev/null || fail "bundle manifest did not bind board evidence path"
grep -Fx "BOOT_EVIDENCE_SHA256=$(sha "$temporary/boot.evidence")" "$temporary/artifacts/bundle/bundle.manifest" >/dev/null || fail "bundle manifest did not bind boot evidence checksum"
cp -- "$temporary/artifacts/bundle/bundle.manifest" "$temporary/bundle.manifest.saved"
sed -i '/^BOARD_EVIDENCE_PATH=/d' "$temporary/artifacts/bundle/bundle.manifest"
expect_failure_message 'bundle manifest is missing: BOARD_EVIDENCE_PATH' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
cp -- "$temporary/bundle.manifest.saved" "$temporary/artifacts/bundle/bundle.manifest"
mkdir -p -- "$temporary/fake-uuu-bin"
cat > "$temporary/fake-uuu-bin/uuu" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -lsusb ]]; then
  if [[ -n "${UUU_DISCOVERY_COUNT:-}" ]]; then
    count=0
    [[ ! -f "$UUU_DISCOVERY_COUNT" ]] || count="$(<"$UUU_DISCOVERY_COUNT")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$UUU_DISCOVERY_COUNT"
  fi
  printf '%s\n' "${UUU_DISCOVERY:-uuu (Universal Update Utility)}"
  printf 'Path\tChip\tPro\tVid\tPid\tBcdVersion\tSerial\n'
  printf '%s\n' '----------------------------------------------------'
  row="${UUU_DISCOVERY_ROW:-1:2	MX7D	SDP:	0x15A2	0x0076	0x0001	}"
  if [[ "${UUU_RACE:-false}" == true && "${count:-0}" -ge 2 ]]; then
    row='2:3	MX7D	SDP:	0x15A2	0x0076	0x0001	'
  fi
  printf '%s\n' "$row"
  [[ -z "${UUU_EXTRA_SDP_ROW:-}" ]] || printf '%s\n' "$UUU_EXTRA_SDP_ROW"
  exit 0
fi
printf '%s\t' "$@" >> "${UUU_CALLS:?}"
printf '\n' >> "$UUU_CALLS"
printf 'fake UUU output\n'
exit "${UUU_FLASH_STATUS:-0}"
EOF
chmod +x "$temporary/fake-uuu-bin/uuu"
dry_run_output="$(UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle")"
[[ ! -e "$temporary/uuu-calls" ]] || fail "dry run invoked UUU flashing"
[[ "$dry_run_output" == *"resolved UUU command: uuu -m 1:2 $temporary/artifacts/bundle/flash.uuu"* && "$dry_run_output" == *'payload RAW_IMAGE_FILE=image.raw SHA256='* &&
   "$dry_run_output" == *'payload SPL_FILE=spl.bin SHA256='* && "$dry_run_output" == *'payload UBOOT_FILE=u-boot.imx SHA256='* &&
   "$dry_run_output" == *'payload UUU_SCRIPT_FILE=flash.uuu SHA256='* ]] ||
  fail "dry run did not display the resolved command and payload checksum"
expect_failure_message 'found 0' \
  env UUU_DISCOVERY_ROW=$'1:2\tMX7D\tSDP:\t0x15A2\t0x9999\t0x0076\t' UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
expect_failure_message 'among 2 SDP-family row(s)' \
  env UUU_EXTRA_SDP_ROW=$'1:3\tMX6Q\tSDP:\t0x15A2\t0x0076\t0x0001\t' UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
expect_failure_message 'among 2 SDP-family row(s)' \
  env UUU_EXTRA_SDP_ROW=$'1:3\tMX7D\tSDPS:\t0x15A2\t0x0076\t0x0001\t' UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
expect_failure_message 'among 2 SDP-family row(s)' \
  env UUU_EXTRA_SDP_ROW=$'1:3\tMX7D\tSDPXYZ:\t0x15A2\t0x0076\t0x0001\t' UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
bundle_hash="$(sha "$temporary/artifacts/bundle/bundle.manifest")"
mkdir -p -- "$temporary/escaped-logs"
ln -s -- "$temporary/escaped-logs" "$temporary/artifacts/bundle/logs"
expect_failure_message 'flash logs path must not be a symbolic link' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle "FLASH_BUNDLE_SHA256=$bundle_hash" --confirm-device 'FLASH_DEVICE=imx7d-sdp-15a2:0076'
rm -- "$temporary/artifacts/bundle/logs"
expect_failure_message 'first operator confirmation does not match this bundle' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash
expect_failure_message 'first operator confirmation does not match this bundle' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle 'FLASH_BUNDLE_SHA256=wrong'
expect_failure_message 'second operator confirmation does not match discovered device identity' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle "FLASH_BUNDLE_SHA256=$bundle_hash" --confirm-device 'FLASH_DEVICE=imx7d-sdp-ffff:ffff'
[[ ! -e "$temporary/uuu-calls" ]] || fail "bad confirmations invoked fake UUU"
printf 'tampered image\n' > "$temporary/artifacts/bundle/image.raw"
expect_failure_message 'SHA-256 mismatch' \
  env UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle"
[[ ! -e "$temporary/uuu-calls" ]] || fail "tampered bundle invoked fake UUU"
printf 'raw image\n' > "$temporary/artifacts/bundle/image.raw"
expect_failure_message 'fresh discovery changed expected i.MX7D SDP path before flashing' \
  env UUU_RACE=true UUU_DISCOVERY_COUNT="$temporary/race-discovery-count" UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle "FLASH_BUNDLE_SHA256=$bundle_hash" --confirm-device 'FLASH_DEVICE=imx7d-sdp-15a2:0076'
[[ ! -e "$temporary/uuu-calls" ]] || fail "discovery race invoked UUU flashing"
UUU_DISCOVERY_COUNT="$temporary/positive-discovery-count" UUU_CALLS="$temporary/uuu-calls" PATH="$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle "FLASH_BUNDLE_SHA256=$bundle_hash" --confirm-device 'FLASH_DEVICE=imx7d-sdp-15a2:0076' >/dev/null
grep -E -- $'-m\t1:2\t.*/\.flash-snapshot\..*/flash\.uuu\t' "$temporary/uuu-calls" >/dev/null || fail "confirmed flash did not bind fake UUU to verified payload snapshot"
[[ "$(<"$temporary/positive-discovery-count")" == 2 ]] || fail "flash did not rediscover before fake UUU invocation"
mkdir -p -- "$temporary/fake-tee-bin"
cat > "$temporary/fake-tee-bin/tee" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output="${!#}"
cat > "$output"
exit "${TEE_STATUS:-0}"
EOF
chmod +x "$temporary/fake-tee-bin/tee"
expect_failure_message 'UUU output logging failed (tee exit 9; UUU exit 7)' \
  env UUU_FLASH_STATUS=7 TEE_STATUS=9 UUU_DISCOVERY_COUNT="$temporary/failure-discovery-count" UUU_CALLS="$temporary/uuu-calls" \
  PATH="$temporary/fake-tee-bin:$temporary/fake-uuu-bin:$PATH" \
  "$repo_root/scripts/flash-bundle.sh" --bundle "$temporary/artifacts/bundle" --flash \
  --confirm-bundle "FLASH_BUNDLE_SHA256=$bundle_hash" --confirm-device 'FLASH_DEVICE=imx7d-sdp-15a2:0076'
failure_result="$(rg -l -F 'uuu_exit_code=7' "$temporary/artifacts/bundle/logs")"
grep -Fx 'tee_exit_code=9' "$failure_result" >/dev/null || fail "flash result did not record tee status separately"
printf 'phase-2 workflow checks passed\n'
