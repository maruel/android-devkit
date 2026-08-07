# Other OSes

## Android

This is to \*build\* android. **Only support imx8 and imx9 from what I understand**.  
[download.technexion.com/development\_resources/NXP/android/14.0/proprietary-package/](https://download.technexion.com/development_resources/NXP/android/14.0/proprietary-package/)  
[https://download.technexion.com/development\_resources/NXP/android/14.0/proprietary-package/imx-android-14.0.0\_2.2.0.tar.gz](https://download.technexion.com/development_resources/NXP/android/14.0/proprietary-package/imx-android-14.0.0_2.2.0.tar.gz)

## buildroot

[https://github.com/buildroot/buildroot/tree/master/board/technexion/imx7dpico](https://github.com/buildroot/buildroot/tree/master/board/technexion/imx7dpico)

## Debian

[https://developer.technexion.com/docs/how-to-build-and-deploy-debian-using-flexbuild](https://developer.technexion.com/docs/how-to-build-and-deploy-debian-using-flexbuild)

```
sudo apt install python-is-python3

git clone https://github.com/TechNexion/tn_debian_flexbuild
cd tn_debian_flexbuild
. setup.env
bld docker
```

Once in docker:

```
. setup.env
bld host-dep
bld -m imx7ulpevk
```

Utilise tn-scarthgap\_6.6.52\_2.2.0\_20241230.  
Ce n'est pas le bon board, je veux pico-imx7.

Random: [https://forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429](https://forum.digikey.com/t/debian-getting-started-with-the-pico-pi-imx7/12429)  
Questions: [https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/4](https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/4)

## Ubuntu

Building an image:  
[https://developer.technexion.com/docs/building-ubuntu-2204-xfce](https://developer.technexion.com/docs/building-ubuntu-2204-xfce)  
uuu: " Download: prebuilt binary "  
password: ubuntu

Manuel:

```
sudo apt update
sudo apt install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf crossbuild-essential-armhf flex bison
git clone https://github.com/TechNexion/linux-tn-imx
cd linux-tn-imx
git checkout tn-kirkstone_5.15.71-2.2.2_20240220
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- defconfig
cd drivers/net/wireless/broadcom/brcm80211/brcmfmac/
```

Automatique:

\# gawk wget git git-core diffstat unzip texinfo gcc-multilib build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping libsdl1.2-dev xterm language-pack-en coreutils texi2html file docbook-utils python-pysqlite2 help2man desktop-file-utils libgl1-mesa-dev libglu1-mesa-dev mercurial autoconf automake groff curl lzop asciidoc u-boot-tools libreoffice-writer sshpass ssh-askpass zip xz-utils kpartx vim screen bison flex debootstrap qemu-system-arm qemu-user-static libssl-dev 

```
sudo apt update
sudo apt-get install gcc-arm-linux-gnueabi

git clone https://github.com/TechNexion-customization/ubuntu-tn-imxcd ubuntu-tn-imx
LANG=C make all PLATFORM="pico-imx7d"

# Fail
cd output/kernel/linux-tn-imx/drivers/net/wireless/broadcom/brcm80211/brcmfmac

```

It downloads [https://github.com/TechNexion/qcacld-2.0](https://github.com/TechNexion/qcacld-2.0)

Pas besoin de \-j, il semble déjà être assez parallèle.

[https://www.linkedin.com/in/hakahu/](https://www.linkedin.com/in/hakahu/)

## Zephyr

si jamais je veux essayer un autre OS. Semble un paquet de trouble  
[https://docs.zephyrproject.org/latest/boards/technexion/pico\_pi/doc/index.html](https://docs.zephyrproject.org/latest/boards/technexion/pico_pi/doc/index.html)  
