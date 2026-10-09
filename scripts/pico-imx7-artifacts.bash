# Shared identity and validation boundary for image and existing-target inputs.
# Consumers supply fail(); validated inventory variables are shared with callers.
# shellcheck disable=SC2034
readonly KERNEL_COMMIT='9339d9595f0d5192cf154b6fe6b98f43e8226fe8'
readonly TARGET_RELEASE='5.15.71'
readonly TARGET_VERMAGIC='5.15.71 SMP preempt mod_unload modversions ARMv7 p2v8 '
readonly PREPARED_CONFIG_SHA256='36d36040492a62bd7593cdc03311c7d7e7f65bac1ba1e40272f26cb278365b99'
readonly AP6335_FIRMWARE_SHA256='16cbdac88d49c2f76eea461cf6c81e3866572f850fe29be726555549ac1c8f55'
readonly AP6335_NVRAM_SHA256='3c4d7058803bd54d0443de0c272b6abd67e5f28f5ba11ecaf790331758f24cf4'
readonly BOOT_KERNEL_SHA256='5dc157521db63d3ba5223fd9680f5336b0da012b392454b7fc6b5e60de7e9756'
# shellcheck disable=SC2034
readonly BOARD_MODEL='TechNexion PICO-IMX7D with BCM4339 WLAN module and PI baseboard'
declare -a module_paths=(
  drivers/net/wireless/broadcom/brcm80211/brcmutil/brcmutil.ko
  drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko
  drivers/media/platform/mxc/capture/mx6s_capture.ko
  drivers/media/platform/mxc/capture/mxc_v4l2_capture.ko
  drivers/media/platform/mxc/capture/v4l2-int-device.ko
  drivers/media/platform/mxc/capture/mxc_mipi_csi.ko
  drivers/media/platform/mxc/capture/ov5645_camera_mipi_v2.ko
)
declare -a firmware_names=(
  'brcmfmac4339-sdio.bin' 'brcmfmac4339-sdio.fsl,pico-imx7d.bin'
  'brcmfmac4339-sdio.txt' 'brcmfmac4339-sdio.fsl,pico-imx7d.txt'
)
declare -a module_names=() module_destinations=() module_hashes=() firmware_destinations=()
for artifact_path in "${module_paths[@]}"; do
  module_names+=("${artifact_path##*/}")
  module_destinations+=("kernel/$artifact_path")
done
for artifact_name in "${firmware_names[@]}"; do firmware_destinations+=("brcm/$artifact_name"); done
unset artifact_path artifact_name
artifact_sha256() {
  local digest
  digest=$(sha256sum -- "$1")
  printf '%s\n' "${digest%% *}"
}
artifact_file() {
  [[ -s $1 && -f $1 && ! -L $1 ]] || fail "missing or unsafe artifact: $1"
}
module_vermagic() {
  local values
  values=$(LC_ALL=C strings -a -- "$1" | awk -F= '$1=="vermagic" {print substr($0,10)}')
  [[ -n $values && $values != *$'\n'* ]] || fail "module needs exactly one literal vermagic: $1"
  printf '%s\n' "$values"
}
validate_pico_modules() {
  local module_build=$1
  local line key value current='' pending='' index found header module digest
  local -A fields=() recorded=()
  [[ $module_build == /* && -d $module_build && ! -L $module_build ]] || fail 'artifact roots must be absolute directories'
  module_record=$module_build/modules.record
  modules_dir=$module_build/modules
  boot_dtb=$module_build/boot/imx7d-pico-pi.dtb
  artifact_file "$module_record"
  [[ $(stat -c %s -- "$module_record") -le 16384 ]] || fail 'oversized module record'
  [[ -d $modules_dir && ! -L $modules_dir && -d $module_build/boot && ! -L $module_build/boot ]] || fail 'unsafe artifact subdirectory'
  artifact_file "$boot_dtb"
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == *=* ]] || fail 'malformed module record'
    key=${line%%=*}; value=${line#*=}
    case $key in
      module)
        [[ -z $current ]] || fail 'incomplete module association'
        found=false
        for module in "${module_paths[@]}"; do [[ $value != "$module" ]] || found=true; done
        [[ $found == true && ! -v recorded[$value] ]] || fail "unsupported or duplicate recorded module: $value"
        current=$value; pending=''
        ;;
      module_sha256)
        [[ -n $current && -z $pending && $value =~ ^[a-f0-9]{64}$ ]] || fail 'invalid module checksum association'
        pending=$value
        ;;
      module_vermagic)
        [[ -n $current && -n $pending && $value == "$TARGET_VERMAGIC" ]] || fail 'invalid recorded module vermagic association'
        recorded[$current]=$pending; current=''; pending=''
        ;;
      format|kernel_commit|prepared_config_sha256|build_config_sha256|kernelrelease|expected_vermagic|cross_compile|compiler|boot_dtb|boot_dtb_sha256|compiler_version|compiler_target|compiler_sha256|brcm_dts_sha256|mx6s_720p_limit_patch_sha256|mx6s_stream_close_patch_sha256|ov5645_mode_sync_patch_sha256|ov5645_night_exposure_patch_sha256)
        [[ -z $current && ! -v fields[$key] && -n $value ]] || fail "duplicate or misplaced record field: $key"
        fields[$key]=$value
        ;;
      *) fail "unknown module record field: $key" ;;
    esac
  done < "$module_record"
  [[ -z $current && ${#recorded[@]} == "${#module_paths[@]}" ]] || fail 'missing module record associations'
  for header in format kernel_commit prepared_config_sha256 build_config_sha256 kernelrelease expected_vermagic cross_compile compiler boot_dtb boot_dtb_sha256; do
    [[ -v fields[$header] ]] || fail "missing module identity: $header"
  done
  [[ ${fields[format]} == pico-imx7-ubuntu-22.04-module-build-v1 && ${fields[kernel_commit]} == "$KERNEL_COMMIT" &&
     ${fields[prepared_config_sha256]} == "$PREPARED_CONFIG_SHA256" && ${fields[kernelrelease]} == "$TARGET_RELEASE" &&
     ${fields[expected_vermagic]} == "$TARGET_VERMAGIC" && ${fields[build_config_sha256]} =~ ^[a-f0-9]{64}$ &&
     ${fields[cross_compile]} == arm-linux-gnueabi- && ${fields[compiler]} == /* &&
     ${fields[boot_dtb]} == imx7d-pico-pi.dtb && ${fields[boot_dtb_sha256]} =~ ^[a-f0-9]{64}$ ]] || fail 'module record identity mismatch'
  [[ $(artifact_sha256 "$boot_dtb") == "${fields[boot_dtb_sha256]}" ]] || fail 'DTB does not match its record'
  # Legacy v1 records remain valid; newly attested builds must carry the entire
  # compiler/source/patch identity block, never a partial collection.
  if [[ -v fields[compiler_version] || -v fields[compiler_target] || -v fields[compiler_sha256] ||
        -v fields[brcm_dts_sha256] || -v fields[mx6s_720p_limit_patch_sha256] ||
        -v fields[mx6s_stream_close_patch_sha256] || -v fields[ov5645_mode_sync_patch_sha256] ||
        -v fields[ov5645_night_exposure_patch_sha256] ]]; then
    [[ ${fields[compiler_version]:-} =~ ^12\.[0-9]+(\.[0-9]+)?$ && ${fields[compiler_target]:-} == arm-linux-gnueabi ]] || fail 'invalid compiler attestation'
    for header in compiler_sha256 brcm_dts_sha256 mx6s_720p_limit_patch_sha256 mx6s_stream_close_patch_sha256 ov5645_mode_sync_patch_sha256; do
      [[ ${fields[$header]:-} =~ ^[a-f0-9]{64}$ ]] || fail "missing or invalid source attestation: $header"
    done
  fi
  # Older attested records remain readable; publication requires the current
  # night-exposure identity through require_pico_source_attestation below.
  if [[ -v fields[ov5645_night_exposure_patch_sha256] ]]; then
    [[ ${fields[ov5645_night_exposure_patch_sha256]} =~ ^[a-f0-9]{64}$ ]] || fail 'invalid night exposure patch attestation'
  fi
  module_hashes=()
  for index in "${!module_paths[@]}"; do
    module=$modules_dir/${module_names[$index]}
    artifact_file "$module"
    digest=${recorded[${module_paths[$index]}]}
    [[ $(artifact_sha256 "$module") == "$digest" ]] || fail "module does not match its record: ${module_names[$index]}"
    header=$(LC_ALL=C readelf -h -- "$module")
    [[ $header =~ Class:[[:space:]]+ELF32 && $header =~ Type:[[:space:]]+REL && $header =~ Machine:[[:space:]]+ARM ]] || fail "module must be an ARM32 ELF relocatable object: $module"
    [[ $(module_vermagic "$module") == "$TARGET_VERMAGIC" ]] || fail "literal module vermagic mismatch: $module"
    module_hashes+=("$digest")
  done
}
validate_pico_artifacts() {
  local firmware_dir=$2 index digest
  [[ $firmware_dir == /* && -d $firmware_dir && ! -L $firmware_dir ]] || fail 'firmware root must be an absolute directory'
  validate_pico_modules "$1"
  for index in "${!firmware_names[@]}"; do
    artifact_file "$firmware_dir/${firmware_names[$index]}"
    digest=$AP6335_FIRMWARE_SHA256
    [[ ${firmware_names[$index]} != *.txt ]] || digest=$AP6335_NVRAM_SHA256
    [[ $(artifact_sha256 "$firmware_dir/${firmware_names[$index]}") == "$digest" ]] || fail "firmware checksum mismatch: ${firmware_names[$index]}"
  done
}

require_pico_source_attestation() {
  local record=$1 repository=$2 key relative expected actual
  # Call after validate_pico_modules; known fields are unique and bounded.
  while IFS=$'\t' read -r key relative; do
    expected=$(awk -F= -v key="$key" '$1==key {print $2}' "$record")
    artifact_file "$repository/$relative"
    actual=$(artifact_sha256 "$repository/$relative")
    [[ $expected == "$actual" ]] || fail "build source attestation differs: $key"
  done <<'SOURCES'
brcm_dts_sha256	configs/pico-imx7/imx7d-pico-pi-brcm.dts
mx6s_720p_limit_patch_sha256	patches/pico-imx7/mx6s-csi-720p-limit.patch
mx6s_stream_close_patch_sha256	patches/pico-imx7/mx6s-csi-stream-close.patch
ov5645_mode_sync_patch_sha256	patches/pico-imx7/ov5645-v4l2-mode-sync.patch
ov5645_night_exposure_patch_sha256	patches/pico-imx7/ov5645-bounded-night-exposure.patch
SOURCES
}
