#!/usr/bin/env bash
# Rebuild the pinned Ubuntu kernel modules into a new validated output directory.
set -euo pipefail

readonly KERNEL_COMMIT='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
readonly KERNEL_URL='https://github.com/TechNexion/linux-tn-imx.git'

usage() {
  printf '%s\n' 'usage: build-drivers.sh [--cross-gcc /absolute/path/to/gcc-12] [--output-dir /absolute/new/path]' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
artifacts_dir="$script_dir/artifacts"
checkout="$artifacts_dir/linux-tn-imx"
output_dir="$artifacts_dir/module-build"
prepared_config="$script_dir/configs/pico-imx7/ubuntu-22.04-5.15.71-prepared.config"
cross_gcc=/usr/bin/arm-linux-gnueabi-gcc-12
while (($#)); do
  case $1 in
    --cross-gcc|--output-dir)
      (($# >= 2)) || usage
      case $1 in --cross-gcc) cross_gcc=$2;; --output-dir) output_dir=$2;; esac
      shift 2;;
    *) usage;;
  esac
done
[[ $cross_gcc == /* && $output_dir == /* ]] || fail 'compiler and output paths must be absolute'
[[ -x $cross_gcc && -f $cross_gcc && ! -L $cross_gcc ]] || fail "GCC 12 ARM compiler missing: $cross_gcc"

command -v git >/dev/null 2>&1 || fail 'git is required'
[[ ! -e "$output_dir" && ! -L "$output_dir" ]] ||
  fail "refusing to overwrite existing build output: $output_dir"
mkdir -p -- "$artifacts_dir"
if [[ ! -e "$checkout" ]]; then
  git init -- "$checkout"
  git -C "$checkout" remote add origin "$KERNEL_URL"
  git -C "$checkout" fetch --depth=1 origin "$KERNEL_COMMIT"
  git -C "$checkout" checkout --detach "$KERNEL_COMMIT"
fi
[[ -d "$checkout/.git" && ! -L "$checkout" ]] ||
  fail "kernel checkout is not a Git worktree: $checkout"
if ! git -C "$checkout" cat-file -e "${KERNEL_COMMIT}^{commit}" 2>/dev/null; then
  git -C "$checkout" fetch --depth=1 "$KERNEL_URL" "$KERNEL_COMMIT"
fi
# The builder archives this exact object; an existing developer checkout's HEAD
# and working tree do not influence or need mutation for the build.
exec "$script_dir/scripts/build-pico-imx7-ubuntu-modules.sh" \
  --source-checkout "$checkout" \
  --prepared-config "$prepared_config" \
  --output-dir "$output_dir" \
  --cross-gcc "$cross_gcc"
