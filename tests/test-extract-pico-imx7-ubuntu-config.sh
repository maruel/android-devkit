#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
helper="$repo_root/scripts/extract-pico-imx7-ubuntu-config.sh"
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

fake_bin="$temporary/fake-bin"
mkdir -- "$fake_bin"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  '[[ "$1" == --decompress && "$2" == --stdout ]] || exit 2' \
  'cat' '[[ "${LZOP_EXIT_2:-false}" != true ]] || exit 2' > "$fake_bin/lzop"
chmod +x -- "$fake_bin/lzop"

good_extractor="$temporary/good-extract-ikconfig"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  '[[ -s "$1" ]]' 'printf "%s\\n" "CONFIG_IKCONFIG=y" "CONFIG_IKCONFIG_PROC=y" "CONFIG_TEST=y"' > "$good_extractor"
chmod +x -- "$good_extractor"

bad_extractor="$temporary/bad-extract-ikconfig"
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' \
  '[[ -s "$1" ]]' 'printf "%s\\n" "CONFIG_IKCONFIG=y" "CONFIG_TEST=y"' > "$bad_extractor"
chmod +x -- "$bad_extractor"

zimage="$temporary/zImage"
printf 'prefix' > "$zimage"
dd if=/dev/zero bs=1 count=17378 status=none >> "$zimage"
printf 'compressed-kernel-payload\n' >> "$zimage"
zimage_sha="$(sha "$zimage")"
expected_config="$temporary/expected.config"
printf '%s\n' 'CONFIG_IKCONFIG=y' 'CONFIG_IKCONFIG_PROC=y' 'CONFIG_TEST=y' > "$expected_config"
config_sha="$(sha "$expected_config")"

output="$temporary/output.config"
env PATH="$fake_bin:$PATH" "$helper" \
  --zimage "$zimage" --extract-ikconfig "$good_extractor" --output "$output" \
  --expected-zimage-sha "$zimage_sha" --expected-config-sha "$config_sha"
cmp -- "$expected_config" "$output" || fail 'happy path wrote an unexpected configuration'
[[ -f "$output.provenance" ]] || fail 'happy path did not write provenance'
grep -Fx "zimage_sha256=$zimage_sha" -- "$output.provenance" >/dev/null || fail 'provenance lacks zImage checksum'
grep -Fx "config_sha256=$config_sha" -- "$output.provenance" >/dev/null || fail 'provenance lacks config checksum'
grep -Fx 'lzop_offset_bytes=17384' -- "$output.provenance" >/dev/null || fail 'provenance lacks LZOP offset'

warning_output="$temporary/warning.config"
env LZOP_EXIT_2=true PATH="$fake_bin:$PATH" "$helper" \
  --zimage "$zimage" --extract-ikconfig "$good_extractor" --output "$warning_output" \
  --expected-zimage-sha "$zimage_sha" --expected-config-sha "$config_sha"
cmp -- "$expected_config" "$warning_output" || fail 'LZOP warning path wrote an unexpected configuration'

mismatch_output="$temporary/mismatch.config"
expect_failure_message 'extracted configuration SHA-256 mismatch' env PATH="$fake_bin:$PATH" "$helper" \
  --zimage "$zimage" --extract-ikconfig "$good_extractor" --output "$mismatch_output" \
  --expected-config-sha '0000000000000000000000000000000000000000000000000000000000000000'
[[ ! -e "$mismatch_output" && ! -e "$mismatch_output.provenance" ]] ||
  fail 'checksum mismatch published output'

malformed_output="$temporary/malformed.config"
expect_failure_message 'does not enable CONFIG_IKCONFIG_PROC' env PATH="$fake_bin:$PATH" "$helper" \
  --zimage "$zimage" --extract-ikconfig "$bad_extractor" --output "$malformed_output"
[[ ! -e "$malformed_output" && ! -e "$malformed_output.provenance" ]] ||
  fail 'malformed extractor output published output'

existing_output="$temporary/existing.config"
printf 'do not replace\n' > "$existing_output"
expect_failure_message 'refusing to overwrite existing output' env PATH="$fake_bin:$PATH" "$helper" \
  --zimage "$zimage" --extract-ikconfig "$good_extractor" --output "$existing_output"
[[ "$(<"$existing_output")" == 'do not replace' ]] || fail 'pre-existing output changed'
[[ ! -e "$existing_output.provenance" ]] || fail 'pre-existing output created provenance'

missing_lzop_bin="$temporary/missing-lzop-bin"
mkdir -- "$missing_lzop_bin"
ln -s -- "$(command -v dd)" "$missing_lzop_bin/dd"
expect_failure_message 'required executable not found: lzop' env PATH="$missing_lzop_bin" /bin/bash "$helper" \
  --zimage "$zimage" --extract-ikconfig "$good_extractor" --output "$temporary/missing-lzop.config"

printf 'extract-pico-imx7-ubuntu-config tests passed\n'
