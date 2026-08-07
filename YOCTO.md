# Yocto

[https://developer.technexion.com/docs/building-an-image-with-yocto](https://developer.technexion.com/docs/building-an-image-with-yocto)  
J'aurais dû faire ça: [https://developer.technexion.com/docs/building-an-image-in-docker-container](https://developer.technexion.com/docs/building-an-image-in-docker-container)  
Vidéo quand même pas pire: [https://www.youtube.com/watch?v=AVkyVh9jhoA](https://www.youtube.com/watch?v=AVkyVh9jhoA)  
See branches at: [https://github.com/TechNexion/tn-imx-yocto-manifest](https://github.com/TechNexion/tn-imx-yocto-manifest)

## Yocto in docker

### Building docker image

```
wget https://raw.githubusercontent.com/TechNexion/meta-tn-imx-bsp/mickledore_6.1.55-2.2.0-stable/tools/container/dockerfile
docker build -t yocto-mickledore .
```

### Running interactive

```
docker run -it -u jenkins -v $(pwd):/home/jenkins/yocto --name yocto yocto-mickledore bash
```

### Restart

```
docker start -i yocto
```

### Running via ssh

```
docker run -d -u jenkins -p 22:22 -v $(pwd):/home/jenkins/yocto -v $HOME/.ssh/authorized_keys:/home/jenkins/.ssh/authorized_keys:ro  --name yocto yocto-mickledore bash
ssh jenkins@$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' yocto)
```

### Configuring docker container

```
cd /home/jenkins/yocto
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

### Getting docker info

```
docker ps -a
docker port yocto
docker inspect yocto
docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' yocto
```

## Yocto on host

```
sudo apt install chrpath diffstat gawk lz4
```

## Building

imx-image-full n'est pas supporté sur imx7d.

### mickledore

```
repo init -u https://github.com/TechNexion/tn-imx-yocto-manifest.git -b mickledore_6.1.y-stable -m imx-6.1.55-2.2.0.xml
repo sync

WIFI_FIRMWARE=n DISTRO=fsl-imx-x11 MACHINE=pico-imx7 BASEBOARD=pi source tn-setup-release.sh -b build

(Configure here)

time bitbake core-image-base
# imx-image-full is not supported on imx7d.
time bitbake imx-image-multimedia

ll build/tmp/deploy/images/pico-imx7/core-image-base-pico-imx7.tar.zst ?
```

### Scarthgap

J'ai essayé dernier release et ça n'a pas marché:

```
repo init -u https://github.com/TechNexion/tn-imx-yocto-manifest.git -b scarthgap_6.6.y-stable -m imx-6.6.52-2.2.0.xml
repo sync
```

### Sumo

Voir détails en bas.

```
repo init -u https://github.com/TechNexion/tn-imx-yocto-manifest.git -b sumo_4.14.y_GA-stable -m imx-4.14.98-2.3.5.xml
repo sync

RF_FIRMWARES=bcrm WIFI_FIRMWARE=y WIFI_MODULE=brcm DISPLAY=lcd DISTRO=fsl-imx-x11 MACHINE=pico-imx7 BASEBOARD=pi source edm-setup-release.sh -b build

(Configure here)

time bitbake core-image-base
time bitbake fsl-image-multimedia
# core-image-sato
```

## Adding firmware

[https://claude.ai/chat/70f60f60-d2d7-4b45-ac24-073912cfdeca](https://claude.ai/chat/70f60f60-d2d7-4b45-ac24-073912cfdeca)

```
vi build-x11-pico-imx7/conf/local.conf

CORE_IMAGE_EXTRA_INSTALL += "nano"
RF_FIRMWARES = ""
MACHINE_FEATURES += "wifi"
IMAGE_INSTALL += " linux-firmware-brcm-tn"
KERNEL_MODULE_AUTOLOAD += " brcmfmac"

# Not working:

# IMAGE_INSTALL += " kernel-module-brcmfmac "
# KERNEL_FEATURES += "cfg/brcmfmac"
# IMAGE_INSTALL += " linux-firmware-brcmfmac" - halluciné par claude ?

# TODO:
# echo 'CORE_IMAGE_EXTRA_INSTALL += "chromium-x11 rng-tools"' >> build-x11-pico-imx7/conf/local.conf
```

Aussi

```
cd sources/meta-tn-imx-bsp/recipes-kernel/linux-firmware
mkdir files
cd files
tar xvf ../../../linux-firmware-qca-tn.tar.gz
cd ../../../../..
```

[https://community.st.com/t5/stm32-mpus-boards-and-hardware/adding-wlan-to-stm32mp157-dk2-does-not-copy-modules-what-is/td-p/143007](https://community.st.com/t5/stm32-mpus-boards-and-hardware/adding-wlan-to-stm32mp157-dk2-does-not-copy-modules-what-is/td-p/143007)  
KERNEL\_MODULE\_AUTOLOAD:append  \= "brcmfmac"  
IMAGE\_INSTALL:append \= " kernel-module-brcmfmac linux-firmware-brcmfmac "  
(later for space savings)  
IMAGE\_INSTALL \+= " \\ linux-firmware-brcmfmac43430-sdio \\ linux-firmware-brcmfmac43455-sdio \\ "

doesn't work:  
IMAGE\_FSTYPES \+= "sdcard"

[https://github.com/TechNexion/meta-tn-imx-bsp/issues/2](https://github.com/TechNexion/meta-tn-imx-bsp/issues/2)

[https://chatgpt.com/c/679bfdb5-2d68-8003-8742-d223584daf2d](https://chatgpt.com/c/679bfdb5-2d68-8003-8742-d223584daf2d)

bitbake-layers create-layer meta-maruel  
bitbake-layers add-layer meta-maruel  
rm \-rf meta-maruel/recipes-example/  
mkdir \-p meta-maruel/recipes-kernel/linux  
vi meta-maruel/recipes-kernel/linux/linux-yocto.bbappend  
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"  
SRC\_URI \+= "file://linux-my-custom.cfg"

mkdir \-p meta-maruel/recipes-kernel/linux/files  
vi meta-maruel/recipes-kernel/linux/files/linux-my-custom.cfg  
CONFIG\_BRCMFMAC=m  
CONFIG\_BRCMFMAC\_PROTO\_BCDC=y  
CONFIG\_BRCMFMAC\_USB=y  
CONFIG\_BRCMFMAC\_PCIE=y  
CONFIG\_BRCMFMAC\_SDIO=y

\# Probably need to rebuild the kernel,to be sure  
bitbake \-c cleanall virtual/kernel

\# linux-tn-imx-6.1.55+gitAUTOINC+80c1b69083-r0 do\_fetch

./meta-tn-imx-bsp/conf/machine/pico-imx7.conf

## Splash

splash.bmp est 580x360px  
sources/meta-tn-imx-bsp/recipes-bsp/u-boot/u-boot-tn-imx\_2023.04.bb  
sources/meta-tn-imx-bsp/conf/machine/tn-base.inc  
dans u-boot.

## Flashing

Voir "Flashing".

## Getting info

```
bitbake -s

bitbake -e
bitbake-getvar --value IMAGE_ROOTFS

bitbake-layers show-recipes
```

### Notes

* Caching: [https://wiki.yoctoproject.org/wiki/Enable\_sstate\_cache](https://wiki.yoctoproject.org/wiki/Enable_sstate_cache)  
* OS update: [https://wiki.yoctoproject.org/wiki/System\_Update](https://wiki.yoctoproject.org/wiki/System_Update)  
* This contains many things to help performance: [https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/2823422188/Building+Yocto+Images+using+a+Docker+Container](https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/2823422188/Building+Yocto+Images+using+a+Docker+Container)  
  * Genre \--device=/dev/kvm:/devb/kvm  
* C'est bon: [https://docs.yoctoproject.org/5.0.6/what-i-wish-id-known.html](https://docs.yoctoproject.org/5.0.6/what-i-wish-id-known.html)  
* WIFI\_MODULE=brcm has no effect  
  * Complaint: [https://github.com/TechNexion/tn-imx-yocto-manifest/issues/18](https://github.com/TechNexion/tn-imx-yocto-manifest/issues/18)  
  * Donc c'est mieux de ne pas mettre WIFI\_FIRMWARE=y  
* [https://www.spinics.net/lists/linux-wireless/msg166272.html](https://www.spinics.net/lists/linux-wireless/msg166272.html)  
* 

## Result

```
core-image-minimal-pico-imx7.sdcard.bz2
imx-image-multimedia-pico-imx7.wic.bz2
```

Results at "build/tmp/deploy/images/pico-imx7/

Building Yocto for Pico IMX7: [https://hub.mender.io/t/technexion-pico-pi-imx7/136](https://hub.mender.io/t/technexion-pico-pi-imx7/136)  
Lists dunfell

# Enable apt

Idée intéressante mais bof:  
[https://imxdev.gitlab.io/tutorial/How\_to\_apt-get\_to\_the\_Yocto\_Project\_image/](https://imxdev.gitlab.io/tutorial/How_to_apt-get_to_the_Yocto_Project_image/)

# Sumo 2.5

[https://github.com/TechNexion/tn-imx-yocto-manifest/tree/sumo\_4.14.y\_GA-stable](https://github.com/TechNexion/tn-imx-yocto-manifest/tree/sumo_4.14.y_GA-stable)  
Still lists brcm\!

Sumo docker is too old (ubuntu 16.04) so repo doesn't work anymore.  
[https://github.com/TechNexion/meta-tn-imx-bsp/blob/sumo\_4.14.98-2.0.0\_GA-stable/tools/container/dockerfile](https://github.com/TechNexion/meta-tn-imx-bsp/blob/sumo_4.14.98-2.0.0_GA-stable/tools/container/dockerfile)

# Zeus 3.0

[https://github.com/TechNexion/tn-imx-yocto-manifest/tree/zeus\_5.4.y-stable](https://github.com/TechNexion/tn-imx-yocto-manifest/tree/zeus_5.4.y-stable)  
doesn't list brcm anymore\!  
