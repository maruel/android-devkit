#!/usr/bin/env bash
set -euo pipefail

readonly CROSS_COMPILE='arm-linux-gnueabi-'
# This vendor 5.15 tree cannot complete a GCC 14 build: libahci's
# array_index_nospec() trips its compile-time assertion. GCC 12 is the pinned,
# compatible compiler for the reproducible module build below.
cross_gcc='/usr/bin/arm-linux-gnueabi-gcc-12'

usage() {
  printf '%s\n' 'usage: build-pico-imx7-ubuntu-modules.sh --source-checkout /absolute/path/to/linux-tn-imx --prepared-config /absolute/path/to/ubuntu-22.04-5.15.71-prepared.config --output-dir /absolute/path/to/new-output-directory [--cross-gcc /absolute/path/to/gcc-12]' >&2
  exit 2
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

require_absolute_regular_file() {
  local option_name="$1" path="$2"
  [[ "$path" == /* ]] || fail "$option_name must be an absolute path"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] ||
    fail "$option_name must name a non-empty, non-symlink regular file"
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

source_checkout=""
prepared_config=""
output_dir=""
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
# shellcheck source=scripts/pico-imx7-artifacts.bash
source "$script_dir/pico-imx7-artifacts.bash"
brcm_dts="$script_dir/../configs/pico-imx7/imx7d-pico-pi-brcm.dts"
mx6s_720p_limit_patch="$script_dir/../patches/pico-imx7/mx6s-csi-720p-limit.patch"
mx6s_stream_close_patch="$script_dir/../patches/pico-imx7/mx6s-csi-stream-close.patch"
ov5645_mode_sync_patch="$script_dir/../patches/pico-imx7/ov5645-v4l2-mode-sync.patch"

while (($# > 0)); do
  case "$1" in
    --source-checkout|--prepared-config|--output-dir|--cross-gcc)
      (($# >= 2)) || usage
      case "$1" in
        --source-checkout) source_checkout="$2" ;;
        --prepared-config) prepared_config="$2" ;;
        --output-dir) output_dir="$2" ;;
        --cross-gcc) cross_gcc="$2" ;;
      esac
      shift 2
      ;;
    --help)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

[[ -n "$source_checkout" && -n "$prepared_config" && -n "$output_dir" ]] || usage
[[ "$source_checkout" == /* ]] || fail '--source-checkout must be an absolute path'
[[ "$output_dir" == /* ]] || fail '--output-dir must be an absolute path'
[[ -d "$source_checkout" && ! -L "$source_checkout" ]] ||
  fail '--source-checkout must name a non-symlink directory'
require_absolute_regular_file '--prepared-config' "$prepared_config"
require_absolute_regular_file 'Broadcom hybrid device tree' "$brcm_dts"
require_absolute_regular_file 'MX6S CSI 720p-limit patch' "$mx6s_720p_limit_patch"
require_absolute_regular_file 'MX6S CSI stream-close patch' "$mx6s_stream_close_patch"
require_absolute_regular_file 'OV5645 V4L2 mode synchronization patch' "$ov5645_mode_sync_patch"
[[ ! -e "$output_dir" && ! -L "$output_dir" ]] ||
  fail "refusing to overwrite existing output directory: $output_dir"

for required_command in awk dirname env git grep install make mkdir patch readelf sed sha256sum strings tar wc; do
  require_command "$required_command"
done
require_absolute_regular_file '--cross-gcc' "$cross_gcc"
[[ -x "$cross_gcc" ]] || fail "compiler is not executable: $cross_gcc"
compiler_version=$(env -i PATH=/usr/bin:/bin LC_ALL=C "$cross_gcc" -dumpfullversion)
compiler_target=$(env -i PATH=/usr/bin:/bin LC_ALL=C "$cross_gcc" -dumpmachine)
[[ $compiler_version == 12.* && $compiler_target == arm-linux-gnueabi ]] ||
  fail 'compiler must be GCC 12 targeting arm-linux-gnueabi'
readonly cross_gcc compiler_version compiler_target
compiler_sha=$(sha256_file "$cross_gcc")
brcm_dts_sha=$(sha256_file "$brcm_dts")
mx6s_720p_limit_patch_sha=$(sha256_file "$mx6s_720p_limit_patch")
mx6s_stream_close_patch_sha=$(sha256_file "$mx6s_stream_close_patch")
ov5645_mode_sync_patch_sha=$(sha256_file "$ov5645_mode_sync_patch")
readonly compiler_sha brcm_dts_sha mx6s_720p_limit_patch_sha mx6s_stream_close_patch_sha ov5645_mode_sync_patch_sha

prepared_config_sha="$(sha256_file "$prepared_config")"
[[ "$prepared_config_sha" == "$PREPARED_CONFIG_SHA256" ]] ||
  fail 'prepared config SHA-256 does not match the approved derived configuration'
git -C "$source_checkout" cat-file -e "${KERNEL_COMMIT}^{commit}" ||
  fail "source checkout does not contain required commit: $KERNEL_COMMIT"

output_parent="$(dirname -- "$output_dir")"
readonly output_parent
[[ -d "$output_parent" && ! -L "$output_parent" ]] ||
  fail '--output-dir parent must be an existing, non-symlink directory'

mkdir -- "$output_dir"
source_stage="$output_dir/source-stage"
build_dir="$output_dir/build"
modules_dir="$output_dir/modules"
boot_dir="$output_dir/boot"
mkdir -- "$source_stage" "$build_dir" "$modules_dir" "$boot_dir"

git -C "$source_checkout" archive --format=tar "$KERNEL_COMMIT" |
  tar -xf - -C "$source_stage"
[[ ! -d "$source_stage/.git" ]] || fail 'Git-free source staging unexpectedly contains .git metadata'
patch --batch --forward --fuzz=0 -p1 --directory="$source_stage" \
  --input="$mx6s_720p_limit_patch" ||
  fail 'MX6S CSI 720p-limit patch did not apply exactly'
patch --batch --forward --fuzz=0 -p1 --directory="$source_stage" \
  --input="$mx6s_stream_close_patch" ||
  fail 'MX6S CSI stream-close patch did not apply exactly'
patch --batch --forward --fuzz=0 -p1 --directory="$source_stage" \
  --input="$ov5645_mode_sync_patch" ||
  fail 'OV5645 V4L2 mode synchronization patch did not apply exactly'
install -m 0644 -- "$prepared_config" "$build_dir/.config"
install -m 0644 -- "$brcm_dts" "$source_stage/arch/arm/boot/dts/imx7d-pico-pi-brcm.dts"

make_command=(/usr/bin/make -C "$source_stage" O="$build_dir" ARCH=arm
  CROSS_COMPILE="$CROSS_COMPILE" CC="$cross_gcc")
build_environment=(env -i PATH=/usr/bin:/bin LC_ALL=C TZ=UTC
  KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=offline)

"${build_environment[@]}" "${make_command[@]}" olddefconfig
kernelrelease="$("${build_environment[@]}" "${make_command[@]}" -s kernelrelease)"
[[ "$kernelrelease" == "$TARGET_RELEASE" ]] ||
  fail "kernel release mismatch: expected $TARGET_RELEASE, got ${kernelrelease:-nothing}"
"${build_environment[@]}" "${make_command[@]}" -j4
[[ -f "$build_dir/Module.symvers" && ! -L "$build_dir/Module.symvers" && -s "$build_dir/Module.symvers" ]] ||
  fail 'full kernel build did not produce Module.symvers'
"${build_environment[@]}" "${make_command[@]}" M=drivers/net/wireless/broadcom/brcm80211 modules
"${build_environment[@]}" "${make_command[@]}" M=drivers/media/platform/mxc/capture modules
"${build_environment[@]}" "${make_command[@]}" imx7d-pico-pi-brcm.dtb

declare -a record_lines=(
  'format=pico-imx7-ubuntu-22.04-module-build-v1'
  "kernel_commit=$KERNEL_COMMIT"
  "prepared_config_sha256=$prepared_config_sha"
  "build_config_sha256=$(sha256_file "$build_dir/.config")"
  "kernelrelease=$kernelrelease"
  "expected_vermagic=$TARGET_VERMAGIC"
  "cross_compile=$CROSS_COMPILE"
  "compiler=$cross_gcc"
  "compiler_version=$compiler_version"
  "compiler_target=$compiler_target"
  "compiler_sha256=$compiler_sha"
  "brcm_dts_sha256=$brcm_dts_sha"
  "mx6s_720p_limit_patch_sha256=$mx6s_720p_limit_patch_sha"
  "mx6s_stream_close_patch_sha256=$mx6s_stream_close_patch_sha"
  "ov5645_mode_sync_patch_sha256=$ov5645_mode_sync_patch_sha"
)

for module_path in "${module_paths[@]}"; do
  source_module="$build_dir/$module_path"
  output_module="$modules_dir/$(basename -- "$module_path")"
  [[ -f "$source_module" && ! -L "$source_module" && -s "$source_module" ]] ||
    fail "required module was not produced: $module_path"
  readelf -h -- "$source_module" | grep -Eq 'Machine:.*ARM' ||
    fail "module is not an ARM ELF object: $module_path"
  vermagic="$(module_vermagic "$source_module")"
  [[ "$vermagic" == "$TARGET_VERMAGIC" ]] ||
    fail "module vermagic mismatch for $module_path: $vermagic"
  install -m 0644 -- "$source_module" "$output_module"
  record_lines+=("module=$module_path" "module_sha256=$(sha256_file "$output_module")" "module_vermagic=$vermagic")
done

source_dtb="$build_dir/arch/arm/boot/dts/imx7d-pico-pi-brcm.dtb"
output_dtb="$boot_dir/imx7d-pico-pi.dtb"
[[ -f "$source_dtb" && ! -L "$source_dtb" && -s "$source_dtb" ]] ||
  fail 'required Broadcom device tree was not produced'
install -m 0644 -- "$source_dtb" "$output_dtb"
record_lines+=(
  'boot_dtb=imx7d-pico-pi.dtb'
  "boot_dtb_sha256=$(sha256_file "$output_dtb")"
)

[[ $(sha256_file "$cross_gcc") == "$compiler_sha" ]] || fail 'compiler changed during build'
printf '%s\n' "${record_lines[@]}" > "$output_dir/modules.record"
validate_pico_modules "$output_dir"
require_pico_source_attestation "$output_dir/modules.record" "$script_dir/.."
printf 'built and ABI-validated Pico i.MX7 Ubuntu modules: %s\n' "$output_dir"
