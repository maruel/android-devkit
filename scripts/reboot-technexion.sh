#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly ssh_helper="$script_dir/ssh-technexion.sh"
readonly initial_wait_seconds=40
readonly retry_count=6
readonly retry_delay_seconds=5

[[ -x "$ssh_helper" ]] || {
  printf 'ssh helper is not executable: %s\n' "$ssh_helper" >&2
  exit 127
}

"$ssh_helper" sudo -n true
set +e
"$ssh_helper" sudo -n reboot
reboot_status=$?
set -e
if ((reboot_status != 0 && reboot_status != 255)); then
  printf 'reboot command failed with status %d\n' "$reboot_status" >&2
  exit "$reboot_status"
fi

sleep "$initial_wait_seconds"
for ((attempt = 1; attempt <= retry_count; attempt++)); do
  if SSH_TECHNEXION_TIMEOUT_SECONDS=15 "$ssh_helper" true; then
    printf 'TechNexion target %s is reachable after reboot.\n' "${SSH_TECHNEXION_TARGET:-ubuntu@technexion}"
    exit 0
  fi
  if ((attempt < retry_count)); then
    sleep "$retry_delay_seconds"
  fi
done

printf 'TechNexion target did not become reachable after reboot.\n' >&2
exit 1
