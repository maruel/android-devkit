#!/usr/bin/env bash
set -euo pipefail

readonly password='ubuntu'
readonly target='ubuntu@technexion'
readonly default_timeout_seconds=120

timeout_seconds="${SSH_TECHNEXION_TIMEOUT_SECONDS:-$default_timeout_seconds}"
if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
  printf 'SSH_TECHNEXION_TIMEOUT_SECONDS must be a positive integer, got: %s\n' \
    "$timeout_seconds" >&2
  exit 2
fi
readonly timeout_seconds

timeout_path="$(command -v timeout || true)"
if [[ -z "$timeout_path" ]]; then
  printf 'timeout executable not found in PATH\n' >&2
  exit 127
fi
readonly timeout_path

sshpass_path="$(command -v sshpass || true)"
if [[ -z "$sshpass_path" ]]; then
  printf 'sshpass executable not found in PATH\n' >&2
  exit 127
fi
readonly sshpass_path

ssh_path="$(command -v ssh || true)"
if [[ -z "$ssh_path" ]]; then
  printf 'ssh executable not found in PATH\n' >&2
  exit 127
fi
readonly ssh_path

exec "$timeout_path" --foreground --signal=TERM --kill-after=10s "${timeout_seconds}s" \
  "$sshpass_path" -p "$password" "$ssh_path" \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  -o ServerAliveInterval=5 \
  -o ServerAliveCountMax=3 \
  "$target" "$@"
