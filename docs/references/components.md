# Wi-Fi and camera evidence

## Wi-Fi

The downloaded image calls the radio QCA, but runtime SDIO enumeration on the
actual board reports Broadcom `0x02d0:0x4335`; the vendor driver identifies it
as BCM4339/2. The radio is therefore the AP6335/Broadcom path. [Ubuntu workflow](../workflows/ubuntu.md)

For a Broadcom path, the evidence names `brcmfmac`, `brcmutil`, AP6335 firmware
files, and an NVRAM override. The QCA DTB caused an HT-clock timeout; selecting
the BRCM DTB and the AP6335 firmware created `wlan0`. [Ubuntu workflow](../workflows/ubuntu.md)

An older Yocto attempt reported `WIFI_MODULE=brcm` as ignored; that historical
note does not apply to the verified Ubuntu boot flow.

## Camera

The notes point to an OV5645 camera and record failed/unfinished V4L2 work.
They do not establish whether `ov5640_camera_mipi_v2.ko` is the needed module
or whether the selected image has the matching device-tree/media stack.
[Ubuntu source note](../source-notes/UBUNTU.md)

Phase 2 evidence required: target kernel release and config, enabled camera
device-tree node, module paths/ABI, firmware requirements if any, and the
expected `v4l2-ctl --list-devices` plus format-enumeration result.
