# Digikey forum

[https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/9?u=maruel](https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/9?u=maruel)

[https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/10?u=maruel](https://forum.digikey.com/t/pico-pi-imx7-using-later-kernels-since-5-6-x/11317/10?u=maruel)

—

(was marked as spam)  
https://wireless.docs.kernel.org/en/latest/en/users/drivers/brcm80211.html seems to be what I’m looking for. BCM4335/BCM4339 are explicitly supported by brcmfmac. It seems to me that the problem is that the driver is not compiled in the kernel. This is odd if this is indeed the problem.

—

The chip is clearly a AP6335.  
\!\[PXL\_20250130\_135929961|663x500\](upload://ndlGvpzMVxjUfcdeqEs0fAxbIeI.jpeg)

Fascinating that searching for \[site:ampak.com.tw ap6335\] leads to one earning calls PDF and that's it. Even more fascinating is that it states: \`Wi-Fi 802.11ac+Bluetooth(4.0)+GPS+FM\`.

What, GPS? I'll ignore this as I don't think there's any software support.

Various sources on the internet state AP6335 is indeed using a broadcom under the hood, more specifically a BCM4339. So everything makes more sense now\!

Beside Debian,

I tried building with yocto and even if I specify \`WIFI\_MODULE=brcm\`, it still ends up building with the qualcomm QCA9377 driver. Reference: https://developer.technexion.com/docs/building-an-image-with-yocto.

At this point I'll ask at github.com/TechNexion/meta-tn-imx-bsp.

Thanks for following along. :)

—-

# github issue

\#\# Context

Following instructions at https://developer.technexion.com/docs/building-an-image-with-yocto

Board: imx7d (android things edition) with a AP6335 wifi package using a BCM4339 under the hood.

\!\[Image\](https://github.com/user-attachments/assets/e482334f-fea9-4e8b-8ddb-2f55b0b3eafd)

\#\# Reproduction steps

Build docker with the official yocto mickledore dockerfile by technexion:

\`\`\`  
wget https://raw.githubusercontent.com/TechNexion/meta-tn-imx-bsp/mickledore\_6.1.55-2.2.0-stable/tools/container/dockerfile  
docker build \-t yocto-mickledore .  
\`\`\`

Run the container interactive, mapping the current working directory and build core-image-base for broadcom wifi drver:

\`\`\`  
docker run \-it \-u jenkins \-v $(pwd):/home/jenkins/yocto \--name yocto yocto-mickledore bash

\# now inside docker container:

cd /home/jenkins/yocto  
git config \--global user.email "\[you@example.com\](mailto:you@example.com)"  
git config \--global user.name "Your Name"  
repo init \-u https://github.com/TechNexion/tn-imx-yocto-manifest.git \-b mickledore\_6.1.y-stable \-m imx-6.1.55-2.2.0.xml  
repo sync

WIFI\_FIRMWARE=y WIFI\_MODULE=brcm DISTRO=fsl-imx-x11 MACHINE=pico-imx7 BASEBOARD=pi source tn-setup-release.sh \-b build  
time bitbake core-image-base  
\`\`\`

\#\# Expected

The file at build/tmp/deploy/images/pico-imx7/core-image-base-pico-imx7.tar.zst contains broadcom drivers.

\#\# Actual

The image contains QCA drivers. WIFI\_MODULE is effectively ignored.

[https://github.com/TechNexion/tn-imx-yocto-manifest/issues/18](https://github.com/TechNexion/tn-imx-yocto-manifest/issues/18)  
