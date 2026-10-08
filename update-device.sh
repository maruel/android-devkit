#!/usr/bin/env bash
# Run read-only inventory or an explicitly requested update against selected boards.
set -euo pipefail
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$script_dir/scripts/update-pico-imx7-device.sh" "$@"
