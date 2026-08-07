# Wi-Fi and camera evidence

## Wi-Fi

The notes contain conflicting hardware descriptions: one lists QCA9377, while
the investigation asserts AP6335 with BCM4339 based on external internet
sources. Treat the radio identity as unresolved until confirmed from the actual
board and selected image. [Ubuntu source note](../source-notes/UBUNTU.md)
[investigation source note](../source-notes/INVESTIGATION.md)

For a Broadcom path, the evidence names `brcmfmac`, `brcmutil`, AP6335 firmware
files, and an NVRAM override. The only recorded runtime result includes an
HT-clock timeout; no working Wi-Fi result is documented. [Ubuntu source note](../source-notes/UBUNTU.md)

For Yocto, the `WIFI_MODULE=brcm` environment setting is explicitly reported as
ignored, with an issue link retained in the source note. [Yocto source note](../source-notes/YOCTO.md)
[investigation source note](../source-notes/INVESTIGATION.md)

## Camera

The notes point to an OV5645 camera and record failed/unfinished V4L2 work.
They do not establish whether `ov5640_camera_mipi_v2.ko` is the needed module
or whether the selected image has the matching device-tree/media stack.
[Ubuntu source note](../source-notes/UBUNTU.md)

Phase 2 evidence required: target kernel release and config, enabled camera
device-tree node, module paths/ABI, firmware requirements if any, and the
expected `v4l2-ctl --list-devices` plus format-enumeration result.
