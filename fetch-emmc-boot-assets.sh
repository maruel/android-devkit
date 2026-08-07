#!/usr/bin/env bash
set -euo pipefail

readonly PACKAGE_URL='https://download.technexion.com/development_resources/development_tools/installer/imx-mfg-uuu-tool.zip'
readonly PACKAGE_SHA256='53ab56a291afd99a9cdfcb5b105b2c1b1b0aa5dabd43df36499e6358c5852e03'
readonly SPL_MEMBER='imx-mfg-uuu-tool/imx7/pico-imx7/imx7-SPL'
readonly SPL_SHA256='e3dd71ea785b8d74d876354defb3809666ac2321121388482a5ba13166814280'
readonly UBOOT_MEMBER='imx-mfg-uuu-tool/imx7/pico-imx7/imx7-u-boot.img'
readonly UBOOT_SHA256='21622ebf5b5ef40d3fc7e6da5f9d4fbc8b26f40e167d6fd2815b28f628fb5e80'
readonly UUU_MEMBER='imx-mfg-uuu-tool/uuu/linux64/uuu'
readonly UUU_SHA256='92036334f545699c49b577c60510cb866e5cc8761d7a5d5a753bfd127cfe57e2'

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v -- "$1" >/dev/null 2>&1 || fail "required executable not found: $1"
}

sha256_file() {
  local path="$1" digest
  digest="$(sha256sum -- "$path")"
  printf '%s\n' "${digest%% *}"
}

verify_file() {
  local path="$1" expected_sha="$2" label="$3"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]] || fail "$label is missing or unsafe: $path"
  [[ "$(sha256_file "$path")" == "$expected_sha" ]] || fail "$label has an unexpected SHA-256: $path"
}

for required_command in chmod curl dirname mkdir mktemp mv rm sha256sum unzip; do
  require_command "$required_command"
done
script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
artifacts_dir="$script_dir/artifacts/uuu-assets"
package="$artifacts_dir/imx-mfg-uuu-tool.zip"
assets_dir="$artifacts_dir/pico-imx7"
mkdir -p -- "$artifacts_dir"

if [[ -e "$assets_dir" || -L "$assets_dir" ]]; then
  [[ -d "$assets_dir" && ! -L "$assets_dir" ]] || fail 'extracted eMMC boot-assets path is unsafe'
  verify_file "$assets_dir/imx7-SPL" "$SPL_SHA256" 'Pico i.MX7 SPL'
  verify_file "$assets_dir/imx7-u-boot.img" "$UBOOT_SHA256" 'Pico i.MX7 U-Boot'
  verify_file "$assets_dir/uuu" "$UUU_SHA256" 'bundled UUU executable'
  [[ -x "$assets_dir/uuu" ]] ||
    fail 'Pico i.MX7 UUU executable is missing or unsafe'
  printf 'verified Pico i.MX7 eMMC boot assets: %s\n' "$assets_dir"
  exit 0
fi

if [[ -e "$package" || -L "$package" ]]; then
  verify_file "$package" "$PACKAGE_SHA256" 'TechNexion UUU package'
else
  temporary_package="$(mktemp "$artifacts_dir/.imx-mfg-uuu-tool.XXXXXX")"
  trap 'rm -f -- "$temporary_package"' EXIT
  curl --fail --location --proto '=https' --output "$temporary_package" -- "$PACKAGE_URL"
  [[ "$(sha256_file "$temporary_package")" == "$PACKAGE_SHA256" ]] ||
    fail 'downloaded TechNexion UUU package has an unexpected SHA-256'
  mv -- "$temporary_package" "$package"
  trap - EXIT
fi

temporary_dir="$(mktemp -d "$artifacts_dir/.pico-imx7-assets.XXXXXX")"
trap 'rm -rf -- "$temporary_dir"' EXIT
unzip -p "$package" "$SPL_MEMBER" > "$temporary_dir/imx7-SPL"
unzip -p "$package" "$UBOOT_MEMBER" > "$temporary_dir/imx7-u-boot.img"
unzip -p "$package" "$UUU_MEMBER" > "$temporary_dir/uuu"
chmod 0755 -- "$temporary_dir/uuu"
verify_file "$temporary_dir/imx7-SPL" "$SPL_SHA256" 'extracted Pico i.MX7 SPL'
verify_file "$temporary_dir/imx7-u-boot.img" "$UBOOT_SHA256" 'extracted Pico i.MX7 U-Boot'
verify_file "$temporary_dir/uuu" "$UUU_SHA256" 'extracted UUU executable'
mv -- "$temporary_dir" "$assets_dir"
trap - EXIT
printf 'fetched verified Pico i.MX7 eMMC boot assets: %s\n' "$assets_dir"
