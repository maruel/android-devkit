#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
readonly kernel_commit='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
source_checkout="${OV5645_SOURCE_CHECKOUT:-$repo_root/artifacts/kernel-source}"
readonly source_checkout
patch_file="$repo_root/patches/pico-imx7/ov5645-v4l2-mode-sync.patch"
readonly patch_file
target_file='drivers/media/platform/mxc/capture/ov5645_mipi_v2.c'
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
  fail 'OV5645 mode synchronization patch is missing or invalid'
[[ "$(git -C "$source_checkout" rev-parse HEAD)" == "$kernel_commit" ]] ||
  fail 'source checkout is not at the required kernel commit'

git -C "$source_checkout" archive --format=tar "$kernel_commit" |
  tar -xf - -C "$temporary"
[[ -f "$temporary/$target_file" ]] || fail 'fresh archive lacks the OV5645 V2 source'
git -C "$temporary" apply --check -p1 -- "$patch_file"
patch --batch --forward --fuzz=0 -p1 --directory="$temporary" \
  --input="$patch_file" >/dev/null

grep -F 'sensor->streamcap.capturemode, orig_mode);' \
  "$temporary/$target_file" >/dev/null ||
  fail 'S_PARM does not retain the S_FMT-selected mode'
if sed -n '/static int ov5645_s_parm/,/^}/p' "$temporary/$target_file" |
  grep -Fq 'a->parm.capture.capturemode'; then
  fail 'S_PARM still reads the legacy capturemode input'
fi
grep -F 'ret = ov5645_init_mode(sensor, frame_rate,' \
  "$temporary/$target_file" >/dev/null ||
  fail 'stream start does not initialize the selected mode'

expect_patch_failure "$temporary"

mkdir -- "$temporary/bogus"
git -C "$source_checkout" archive --format=tar "$kernel_commit" |
  tar -xf - -C "$temporary/bogus"
sed -i 's/sensor->streamcap.timeperframe = \*timeperframe;/sensor->streamcap.timeperframe = bogus_timeperframe;/' \
  "$temporary/bogus/$target_file"
expect_patch_failure "$temporary/bogus"

printf 'Pico i.MX7 OV5645 V4L2 mode synchronization patch tests passed\n'
