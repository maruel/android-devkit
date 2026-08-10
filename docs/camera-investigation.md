# Current CAM-OV5645 investigation

Status: **not accepted**. The camera binds and `/dev/video1` enumerates modes,
but image integrity and repeated capture are not yet demonstrated.

## Direct target observations

On the inspected target (`5.15.71`), the sensor is `ov5645_camera_mipi_v2` at
I²C `3-003c`. `/dev/video1` is owned by the `mx6s-csi` platform driver from
`mx6s_capture.ko`; it is not driven by the installed but unloaded legacy
`mxc_v4l2_capture.ko` module. The loaded camera modules are
`mxc_mipi_csi.ko` and `ov5645_camera_mipi_v2.ko`.

The current boot DTB uses a 240 MHz MIPI CSI clock and `csis-wclk`. Its
SHA-256 is `2e7cdfd5b6af15b9e5bf25b7a7c247405eabddfdcaa3f0b77a66bfe62f80b9d1`.
A backup of this exact DTB is retained on the target boot partition as
`/imx7d-pico-pi.dtb.camera-investigation-baseline`.

A one-frame 640×480 YUYV capture completed but was black. A one-frame
1280×720 YUYV capture completed but contained green/black diagonal horizontal
corruption. A five-frame 1280×720 capture completed but did not establish
clean, stable images. Larger bounded captures have made the target
unresponsive or reboot, so a successful V4L2 return is not an acceptance
criterion.

## Receiver experiments

Three temporary DTB variants removed `csis-wclk` and respectively selected a
24 MHz, 240 MHz, or driver-default 166 MHz MIPI CSI clock. Each produced a
MIPI CSI `Frame Start` followed by `FIFO Overflow Error` and capture timeout.
The baseline 240 MHz + `csis-wclk` DTB was restored after the experiments.

These observations disprove the earlier claim that a 30-frame VGA capture was
validated. Do not publish or flash a camera-working claim based on sensor
binding, format enumeration, a produced raw file, or a single returned frame.

## Next investigation boundary

The active `mx6s_capture` module is not one of the replacement modules
recorded by the image workflow. Establish whether its source/modversion and
MIPI capture behavior are compatible with the replacement MIPI receiver and
OV5645 driver before changing the supported module set. A sensor test-pattern
experiment was started but did not produce a result, so it is not evidence.
