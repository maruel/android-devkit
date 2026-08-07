#!/usr/bin/env bash
set -euo pipefail

repo_root="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly repo_root
config_dir="$repo_root/configs/pico-imx7"
readonly config_dir
authoritative_config="$config_dir/ubuntu-22.04-5.15.71.config"
prepared_config="$config_dir/ubuntu-22.04-5.15.71-prepared.config"
readonly authoritative_config prepared_config

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

sha256_file() {
  local digest
  digest="$(sha256sum -- "$1")"
  printf '%s\n' "${digest%% *}"
}

[[ -f "$authoritative_config" && ! -L "$authoritative_config" ]] ||
  fail 'authoritative configuration is missing or symlinked'
[[ -f "$prepared_config" && ! -L "$prepared_config" ]] ||
  fail 'prepared configuration is missing or symlinked'
[[ "$(sha256_file "$authoritative_config")" == '7f2c4ccf19a61c80bd43c3e9b85d64d43d7f97bd915a1cb9fcf56c92ad593825' ]] ||
  fail 'authoritative configuration checksum changed'
[[ "$(sha256_file "$prepared_config")" == '614e375075b3abd70dbf3461e12d878531d81a713899ff5923dca416465d445c' ]] ||
  fail 'prepared configuration checksum changed'
cmp -s -- "$authoritative_config" "$prepared_config" &&
  fail 'prepared configuration must not be labeled identical to the image extraction'
grep -Fx 'CONFIG_VIDEO_TEVS=y' -- "$prepared_config" >/dev/null ||
  fail 'prepared configuration lacks the recorded vendor Kconfig default'
grep -Fq 'it is not byte-identical to the image configuration' -- "$repo_root/docs/workflows/ubuntu.md" ||
  fail 'Ubuntu workflow does not distinguish the derived configuration'
placeholder_manifest='phase-2-workflow.manifest'
[[ ! -e "$repo_root/examples/$placeholder_manifest" ]] ||
  fail 'deleted placeholder manifest is still present'

printf 'Pico i.MX7 Ubuntu configuration tests passed\n'
