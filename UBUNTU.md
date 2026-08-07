# TechNexion

Pico i.MX7D: [technexion.com/products/system-on-modules/evk/pico-pi-imx7/](https://www.technexion.com/products/system-on-modules/evk/pico-pi-imx7/)

## Hardware

* CPU: NXP i.MX7: ARM 2x Cortex-A7 and 1x Cortex M4  
* 5" multi-touch display 800x480  
* 512MB DDR3L  
* 4GB eMMC  
* Camera: CAM-OV5645  
* Ethernet: 1x Atheros AR8035 Gigabit LAN (works great)  
* Wifi & Bluetooth: Qualcomm Atheros QCA9377 Wi-Fi 5 802.11 a/b/g/n/ac and BT5  
  * Nope, AP6335 Wi-Fi 802.11ac+Bluetooth(4.0)+GPS+FM  
* USB:  
  * 1x USB 2.0 Host  
  * 1x USB 2.0 OTG (Type-C)  
  * Micro USB debug (I believe for the Cortex M4)

## Official Tools

* Tool to create an image: [github.com/TechNexion/tn\_debian\_flexbuild](https://github.com/TechNexion/tn_debian_flexbuild)  
* flashing tool [github.com/TechNexion/imx-mfgtools-tn](https://github.com/TechNexion/imx-mfgtools-tn) (old release), which is a fork of [github.com/nxp-imx/mfgtools](https://github.com/nxp-imx/mfgtools)  
* uboot: [github.com/TechNexion/u-boot-tn-imx](https://github.com/TechNexion/u-boot-tn-imx)  
* building Ubuntu: [github.com/TechNexion-customization/ubuntu-tn-imx](https://github.com/TechNexion-customization/ubuntu-tn-imx)  
* all repos: [github.com/orgs/TechNexion/repositories?type=all](https://github.com/orgs/TechNexion/repositories?type=all)  
* more repos: [github.com/orgs/TechNexion-customization/repositories](https://github.com/orgs/TechNexion-customization/repositories)

# NXP

[nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf](https://www.nxp.com/docs/en/user-guide/PICO-IMX7UL-USG.pdf)

## Cortex-M4

Maybe toy with it one day? Probably never.  
[https://kb.segger.com/i.MX7Dual](https://kb.segger.com/i.MX7Dual)  
[https://www.nxp.com/docs/en/application-note/AN5317.pdf](https://www.nxp.com/docs/en/application-note/AN5317.pdf)

# Flashing

```
wget -c https://download.technexion.com/images/pico-imx7/pi-lcd800x480/ubuntu-22.04.xz
xz --decompress ubuntu-22.04.xz
```

Then follow steps in flashing, using "ubuntu-22.04" as the image.

## How to configure

* Plug ethernet cable  
* Plug power via USB-C  
* Wait 3 minutes for the first 2 boots.  
* Wait one minute for the Network icon to appear in the top bar  
* Click "Connection Information"  
* Get IP address

ssh from workstation:

```
ssh ubuntu@192.168.1.128
# password: ubuntu

# Query
df -h
# environ 1.8G used, 1.5G free
sudo apt list --installed

# Disable junk to create host AP:
sudo systemctl disable hostapd

# Disable auto update:
sudo systemctl disable apt-daily-upgrade.timer
sudo systemctl disable apt-daily.timer
sudo systemctl disable update-notifier-download.timer

# Cleanup
sudo apt remove --yes --purge firefox ghostscript snap snapd unrar
# too much: gcc-11-base ubuntu-advantage-tools

# Remove broken source:
sudo rm /etc/apt/sources.list.d/vivaldi.list
# Comment out mozilla too:
sudo sed -i 's/^/# /' /etc/apt/sources.list.d/*.list

# Update:
sudo apt update
sudo apt upgrade --purge
sudo apt autoremove --yes --purge
# fonts-droid-fallback* fonts-noto-mono* 
rm -r Documents Downloads Music Pictures Public Templates Videos

# Query
df -h
# environ 1.5G used, 1.8G free

sudo shutdown -r now
```

### Upgrade to Ubuntu 24.04

Via Applications / Terminal Emulator:  
Probably best to exit X and run via a real terminal?

```
do-release-upgrade

# Require 1.2Gb! Better to uninstall a lot first.
```

Faudra essayer par ssh, il se plaint mais je ne pense pas que ce soit un problème.

When it looks hung:

* Ctrl-Alt-F2  
* Login  
* top  
* ps auxf | less  
* sudo shutdown \-r now

It kills NOPASSWD sudoer.

Autologin \+ auto logout? TODO: Trouver pourquoi. Ran over ssh:

```
sudo dpkg –configure -a
sudo apt autoremove --yes --purge
sudo apt clean
sudo rm /var/crash/*
sudo rm /var/log/*.gz
sudo rm /var/log/*.old
# Once everything is good:
sudo rm -rf /var/log/dist-upgrade
```

## Debug

Normal boot duration is 22s

```
sudo dmesg
sudo journalctl -b
sudo systemctl

# Weird
cat /etc/systemd/system/tn_init.service
cat /usr/bin/system_init
(it fails)
```

## Wifi

TODO: Ne fonctionne pas  
[https://forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429\#wifi-ap6335-19](https://forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429#wifi-ap6335-19) maybe?  
sudo modprobe \-v ath10k\_pci

[https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317](https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317)  
"I’ve managed to get the WiFi working perfectly, thank you. I used the AP6335\_4.2 firmware and it’s running brilliantly."

[https://github.com/Freescale/linux-fslc/blob/5.4.x%2Bfslc/arch/arm/boot/dts/imx7d-pico.dtsi](https://github.com/Freescale/linux-fslc/blob/5.4.x%2Bfslc/arch/arm/boot/dts/imx7d-pico.dtsi)  
[https://github.com/rcn-ee/sdk-firmware/tree/master/technexion/Broadcom](https://github.com/rcn-ee/sdk-firmware/tree/master/technexion/Broadcom)  
[https://github.com/rcn-ee/sdk-firmware/tree/master/technexion/Broadcom/AP6335\_4.2/Wi-Fi](https://github.com/rcn-ee/sdk-firmware/tree/master/technexion/Broadcom/AP6335_4.2/Wi-Fi)

Connecter:  
[https://www.makeuseof.com/connect-to-wifi-with-nmcli/](https://www.makeuseof.com/connect-to-wifi-with-nmcli/)

Open terminal:

```
sudo apt install initramfs-tools

mkdir wifi
cd wifi
wget -c https://github.com/rcn-ee/sdk-firmware/raw/refs/heads/master/technexion/Broadcom/AP6335_4.2/Wi-Fi/nvram_ap6335.txt
wget -c https://github.com/rcn-ee/sdk-firmware/raw/refs/heads/master/technexion/Broadcom/AP6335_4.2/Wi-Fi/fw_bcm4339a0_ag.bin
wget -c https://github.com/rcn-ee/sdk-firmware/raw/refs/heads/master/technexion/Broadcom/AP6335_4.2/Wi-Fi/fw_bcm4339a0_ag_apsta.bin
sudo mkdir -p /usr/lib/firmware/brcm
sudo cp * /usr/lib/firmware/brcm
sudo update-initramfs -u -k $(uname -r)

wget -c https://raw.githubusercontent.com/buildroot/buildroot/master/board/technexion/imx7dpico/rootfs_overlay/lib/firmware/brcm/brcmfmac4339-sdio.txt
sudo mkdir -p /usr/lib/firmware/brcm/
sudo cp * /usr/lib/firmware/brcm/
sudo update-initramfs -u -k $(uname -r)

# Configure wifi:
sudo apt install linux-firmware
sudo modprobe -rv ath10k_pci
sudo modprobe -v ath10k_pci

nmcli dev status
```

/media/rootfs c'est pour quand tu créé une image.

Yocto:  
[https://github.com/Freescale/meta-freescale-3rdparty/blob/master/conf/machine/imx7d-pico.conf](https://github.com/Freescale/meta-freescale-3rdparty/blob/master/conf/machine/imx7d-pico.conf)

Open terminal:

```
sudo apt install lshw
sudo lshw
```

## Camera

**TODO: Ne fonctionne pas**  
v4l2-ctl \--list-devices  
v4l2-ctl \--device=/dev/video0 \--all  
v4l2-ctl \--device /dev/video0 \--set-fmt-video=width=1280,height=720,pixelformat=MJPG \--stream-mmap \--stream-to=frame.jpg \--stream-count=1  
unsupported stream type  
v4l2-ctl \--device /dev/video0 \--list-formats-ext  
[https://github.com/technexion-android/platform\_packages\_apps\_Camera2/issues/1](https://github.com/technexion-android/platform_packages_apps_Camera2/issues/1)  
[https://developer.technexion.com/docs/testing-the-ov5645-mipi-csi2-camera-module](https://developer.technexion.com/docs/testing-the-ov5645-mipi-csi2-camera-module)

/lib/modules/5.15.71/kernel/drivers/media/platform/mxc/capture/ov5640\_camera\_mipi\_v2.ko est présent?

gst-inspect-1.0

### Yocto

[https://github.com/TechNexion/tn-imx-yocto-manifest/issues/23](https://github.com/TechNexion/tn-imx-yocto-manifest/issues/23)  
[https://developer.technexion.com/docs/mipi-csi-periph-wb-edm-g](https://developer.technexion.com/docs/mipi-csi-periph-wb-edm-g)

## Display

Update brightness:

```
sudo cat /sys/class/backlight/backlight/actual_brightness
echo 0 | sudo tee /sys/class/backlight/backlight/brightness
echo 7 | sudo tee /sys/class/backlight/backlight/brightness
```

## UI

[https://sillyslux.github.io/fluxbox-wiki/en/wiki/Keyboard-Shortcuts/](https://sillyslux.github.io/fluxbox-wiki/en/wiki/Keyboard-Shortcuts/)  
Need to figure out the full screen hotkey.

## Guides from other people flash

[gist.github.com/liquidx/fd1002ec870a7c13f04a0b8a44744246](https://gist.github.com/liquidx/fd1002ec870a7c13f04a0b8a44744246)  
[gist.github.com/majduk/902dfa3c273f4e3d1e8c29266a2e9610](https://gist.github.com/majduk/902dfa3c273f4e3d1e8c29266a2e9610)  
[forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429](https://forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429)

# Compiling wifi driver

[https://github.com/TechNexion/linux-tn-imx/tree/tn-imx\_5.15.71\_2.2.0-stable](https://github.com/TechNexion/linux-tn-imx/tree/tn-imx_5.15.71_2.2.0-stable)  
9339d9595f0d5192cf154b6fe6b98f43e8226fe8

```
scp ubuntu@192.168.1.78:/proc/config.gz .
gunzip config.gz
cp config .config
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
make menuconfig
# (D)evice Drivers → N(e)twork device support → (W)ireless LAN → (B)roadcom FullMAC WLAN driver (brcmfmac)
Set to "M"
Save
Exit
LANG=C make prepare
LANG=C make modules_prepare
LANG=C make M=drivers/net/wireless/broadcom/brcm80211 modules
LANG=C make M=drivers/net/wireless/broadcom/brcm80211 modules
```

```
scp drivers/net/wireless/broadcom/brcm80211/brcmfmac/brcmfmac.ko  ubuntu@192.168.1.78:.
scp drivers/net/wireless/broadcom/brcm80211/brcmutil/brcmutil.ko  ubuntu@192.168.1.78:.
```

```
sudo cp brcmfmac.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/
sudo cp brcmutil.ko /lib/modules/$(uname -r)/kernel/drivers/net/wireless/
ll /lib/modules/$(uname -r)/kernel/drivers/net/wireless/

# sudo cp nvram_ap6335.txt /lib/firmware/brcm/brcmfmac4339-sdio.fsl,pico-imx7d.txt
wget -c https://github.com/rcn-ee/sdk-firmware/raw/refs/heads/master/technexion/Broadcom/AP6335_4.2/Wi-Fi/fw_bcm4339a0_ag.bin
sudo cp fw_bcm4339a0_ag.bin /lib/firmware/brcm/brcmfmac4339-sdio.fsl,pico-imx7d.bin

sudo depmod -a
sudo modprobe -v brcmfmac

iw dev
```

### Errors

brcmfmac: brcmf\_sdio\_htclk: HT Avail timeout (1000000): clkctl 0x50  
Hard reboot?

### Old

sudo nano /etc/modules  
Add  
brcmutil  
brcmfmac

sudo nano /etc/modprobe.d/brcmfmac.conf  
sudo update-initramfs \-u

[https://forum.digikey.com/t/re-pico-pi-imx7-and-siging-in-um/2537/158](https://forum.digikey.com/t/re-pico-pi-imx7-and-siging-in-um/2537/158)  
Maybe use  tn-kirkstone\_5.15.71-2.2.2\_20240220?