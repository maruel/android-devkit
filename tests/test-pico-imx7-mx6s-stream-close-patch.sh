#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly kernel_commit='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
source_checkout="${MX6S_SOURCE_CHECKOUT:-$repo_root/artifacts/kernel-source}"
readonly source_checkout
patch_file="$repo_root/patches/pico-imx7/mx6s-csi-stream-close.patch"
readonly patch_file
target_file='drivers/media/platform/mxc/capture/mx6s_capture.c'
readonly target_file
temporary="$(mktemp -d)"
readonly temporary
trap 'rm -rf -- "$temporary"' EXIT

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

expect_patch_failure() {
  local source_dir="$1"

  if patch --batch --forward --fuzz=0 -p1 --directory="$source_dir" \
    --input="$patch_file" >/dev/null 2>&1; then
    fail "patch unexpectedly applied to $source_dir"
  fi
}

for command in git patch tar; do
  command -v -- "$command" >/dev/null 2>&1 ||
    fail "required executable not found: $command"
done
[[ -d "$source_checkout" && ! -L "$source_checkout" ]] ||
  fail "source checkout is missing or symlinked: $source_checkout"
[[ -f "$patch_file" && ! -L "$patch_file" && -s "$patch_file" ]] ||
  fail 'MX6S CSI stream-close patch is missing or invalid'
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$kernel_commit" ]] ||
  fail 'source checkout is not at the required kernel commit'

git -C "$source_checkout" archive --format=tar "$kernel_commit" |
  tar -xf - -C "$temporary"
[[ -f "$temporary/$target_file" ]] || fail 'fresh archive lacks the MX6S CSI source'
git -C "$temporary" apply --check -p1 -- "$patch_file"
patch --batch --forward --fuzz=0 -p1 --directory="$temporary" \
  --input="$patch_file" >/dev/null

grep -F 'if (vb2_is_streaming(&csi_dev->vb2_vidq))' \
  "$temporary/$target_file" >/dev/null ||
  fail 'close path does not stop a still-streaming queue'
grep -A1 -F 'if (vb2_is_streaming(&csi_dev->vb2_vidq))' \
  "$temporary/$target_file" |
  grep -F 'v4l2_subdev_call(sd, video, s_stream, 0);' >/dev/null ||
  fail 'close path does not stop the downstream subdevice'

expect_patch_failure "$temporary"
printf 'Pico i.MX7 MX6S CSI stream-close patch tests passed\n'
