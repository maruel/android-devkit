#!/usr/bin/env bash
set -euo pipefail

readonly KERNEL_COMMIT='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
readonly KERNEL_URL='https://github.com/TechNexion/linux-tn-imx.git'

usage() {
  printf '%s\n' 'usage: build-drivers.sh' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

if (($# != 0)); then
  usage
fi
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
artifacts_dir="$script_dir/artifacts"
checkout="$artifacts_dir/linux-tn-imx"
output_dir="$artifacts_dir/module-build"
prepared_config="$script_dir/configs/pico-imx7/ubuntu-22.04-5.15.71-prepared.config"

command -v git >/dev/null 2>&1 || fail 'git is required'
[[ -x /usr/bin/arm-linux-gnueabi-gcc-12 ]] ||
  fail 'install build prerequisites first: sudo apt install --no-install-recommends bc dwarves gcc-12-arm-linux-gnueabi libelf-dev'
[[ ! -e "$output_dir" && ! -L "$output_dir" ]] ||
  fail "refusing to overwrite existing build output: $output_dir"
mkdir -p -- "$artifacts_dir"
if [[ ! -e "$checkout" ]]; then
  git clone -- "$KERNEL_URL" "$checkout"
fi
[[ -d "$checkout/.git" && ! -L "$checkout" ]] ||
  fail "kernel checkout is not a Git worktree: $checkout"
git -C "$checkout" cat-file -e "${KERNEL_COMMIT}^{commit}" ||
  fail "kernel checkout does not contain required commit: $KERNEL_COMMIT"
[[ "$(git -C "$checkout" rev-parse HEAD)" == "$KERNEL_COMMIT" ]] ||
  fail "kernel checkout is not detached at required commit: $KERNEL_COMMIT"
exec "$script_dir/scripts/build-pico-imx7-ubuntu-modules.sh" \
  --source-checkout "$checkout" \
  --prepared-config "$prepared_config" \
  --output-dir "$output_dir"
