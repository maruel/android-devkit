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

The board documentation identifies the tested camera as TechNexion
CAM-OV5645. Ubuntu's inherited device tree instead described an OV5640 through
a PCA9554 at I²C `3-0024`; that expander did not respond, leaving `/dev/video1`
without formats. The older PICO-PI vendor device tree identifies the correct
direct GPIO power-down/reset wiring at I²C `3-003c` and the
`ov5645_mipi_v2` driver.

The delivered hybrid DTB uses that OV5645 wiring while retaining the 5.15
MIPI-CSI receiver's 240 MHz clock and `csis-wclk` setting. The target binds
`ov5645_mipi_v2` at `3-003c` and enumerates YUYV modes through 2592×1944.
The tracked OV5645 mode-sync and MX6S stream-close fixes now make bare V4L2
format capture reliable on the inspected target, including a 300-frame soak.
[Current camera investigation](../camera-investigation.md) · [PICO-PI hardware
manual](https://www.mouser.com/datasheet/2/608/technexion_05242017_PICO-PI-IMX7-1214899.pdf)
