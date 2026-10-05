#!/usr/bin/env bash
set -euo pipefail
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=${script_dir%/scripts}
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }
module_build=''
acceptance_dirs=()
while (($#)); do
  case $1 in
    --module-build|--acceptance-dir)
      (($# >= 2)) || fail "missing value: $1"
      case $1 in --module-build) module_build=$2;; --acceptance-dir) acceptance_dirs+=("$2");; esac
      shift 2;;
    *) fail 'usage: publish-pico-imx7-modules.sh --module-build /path --acceptance-dir /first-update-run --acceptance-dir /second-update-run';;
  esac
done
[[ -n $module_build && ${#acceptance_dirs[@]} == 2 && ${acceptance_dirs[0]} != "${acceptance_dirs[1]}" ]] || fail 'require build and two distinct acceptance runs'
for command in awk grep install mktemp mv readelf realpath rm sha256sum stat strings; do
  command -v "$command" >/dev/null || fail "missing executable: $command"
done
# shellcheck source=scripts/pico-imx7-artifacts.bash
source "$script_dir/pico-imx7-artifacts.bash"
validate_pico_modules "$module_build"
require_pico_source_attestation "$module_record" "$repo_dir"
record_sha=$(artifact_sha256 "$module_record")
accepted_target=''
accepted_boot=''
declare -A seen_acceptance=()
declare -A seen_run_ids=()
for directory in "${acceptance_dirs[@]}"; do
  [[ $directory == "$repo_dir/artifacts/target-updates/"* && -d $directory && ! -L $directory ]] || fail 'acceptance must be a target updater evidence directory'
  directory=$(realpath -e -- "$directory")
  [[ $directory == "$repo_dir/artifacts/target-updates/"* && ! -v seen_acceptance[$directory] ]] || fail 'acceptance directories must be distinct updater runs'
  seen_acceptance[$directory]=1
  artifact_file "$directory/provenance"
  [[ $(stat -c %s -- "$directory/provenance") -le 16384 ]] || fail 'oversized acceptance provenance'
  run_id=$(awk -F= '$1=="run_id" {print $2}' "$directory/provenance")
  [[ $run_id =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || fail 'acceptance lacks a valid updater run identity'
  [[ ! -v seen_run_ids[$run_id] ]] || fail 'acceptances must have different updater run identities; copied evidence is not another run'
  seen_run_ids[$run_id]=1
  [[ $(awk -F= '$1=="module_record_sha256" {print $2}' "$directory/provenance") == "$record_sha" ]] || fail 'acceptance was for a different build'
  target=$(awk '/^target=/ {print}' "$directory/provenance")
  [[ $target =~ ^target=([0-9.]+)[[:space:]]uid=[a-f0-9]{16}[[:space:]]hostname=technexion-[a-f0-9]{1,4}$ ]] || fail 'acceptance must identify one inspected board'
  ip=${BASH_REMATCH[1]}
  [[ -z $accepted_target || $accepted_target == "$target" ]] || fail 'repeat acceptance must cover the same board'
  accepted_target=$target
  artifact_file "$directory/$ip.verification"
  [[ $(stat -c %s -- "$directory/$ip.verification") -le 524288 ]] || fail 'oversized acceptance verification'
  if ! grep -Fx 'camera_acceptance=300 frames 1280x720 YUYV and clean reopen' "$directory/$ip.verification" >/dev/null ||
     ! grep -Fx 'verification=PASS' "$directory/$ip.verification" >/dev/null; then
    fail 'require complete finite camera acceptance and successful verification'
  fi
  boot_id=$(awk -F= '$1=="verification_boot_id" {print $2}' "$directory/$ip.verification")
  [[ $boot_id =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$ ]] || fail 'acceptance lacks a verified boot identity'
  [[ -z $accepted_boot || $accepted_boot == "$boot_id" ]] || fail 'repeat acceptance must succeed during the same boot'
  accepted_boot=$boot_id
done
publication=$repo_dir/prebuilt/pico-imx7/ubuntu-22.04-5.15.71
[[ -d $publication && ! -L $publication ]] || fail 'tracked publication directory is unsafe'
parent=${publication%/*}
stage=$(mktemp -d "$parent/.module-publication.XXXXXX")
previous=$stage/previous
cleanup() {
  # Restore the complete old set if interruption occurs between the two renames.
  if [[ -d $previous && ! -e $publication ]]; then
    if ! mv -- "$previous" "$publication"; then
      printf 'Publication recovery unfinished; complete prior set retained at %s\n' "$previous" >&2
      return 1
    fi
  fi
  rm -rf -- "$stage"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
install -d -- "$stage/new/modules" "$stage/new/boot"
for module in "${module_names[@]}"; do install -m 0644 -- "$modules_dir/$module" "$stage/new/modules/$module"; done
install -m 0644 -- "$boot_dtb" "$stage/new/boot/imx7d-pico-pi.dtb"
install -m 0644 -- "$module_record" "$stage/new/modules.record"
validate_pico_modules "$stage/new"
require_pico_source_attestation "$stage/new/modules.record" "$repo_dir"
mv -- "$publication" "$previous"
mv -- "$stage/new" "$publication"
printf 'Published complete source-attested and twice camera-accepted seven-module set: %s\n' "$publication"
