################################################
Standalone firmware and Linux kernel environment
################################################

.. contents::

This project is a helper project to be able to create a development environment
for QEMU consisting of Linux kernel, U-Boot, Buildroot and QEMU itself.

Prerequisites
=============
TBD, but depending on the setup, you should consider setting up TFTP (see TFTP
instructions further down).


Installation
************

Get the source code
===================
Install ``repo`` by following the installation instructions 
`here <https://source.android.com/setup/build/downloading>`_.

Then initialize the tree 

.. code-block:: bash

    $ mkdir -p <path-to-my-project-root>
    $ cd <path-to-my-project-root>
    $ repo init -u https://github.com/jbech-linaro/manifest.git -b dte

Next sync the actual tree

.. code-block:: bash

    $ repo sync -j4

Compile
=======

.. code-block:: bash

	$ make -j2 toolchains
    $ make -j4

Run
===
.. code-block:: bash

    $ make run-netboot

Configure netboot
=================
At the U-boot prompt (change IP to the IP of your computer where you are doing this)

.. code-block:: bash

    => setenv nbr "dhcp; setenv serverip 192.168.1.110; tftp ${kernel_addr_r} uImage; tftp ${ramdisk_addr_r} rootfs.cpio.uboot; bootm ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr}"
    => saveenv
    => run nbr

If everything goes well, you images shall be fetched from the tftd server and
you should end up with Linux kernel booting and you get a Buildroot prompt.

TFTP
****
Setup the tftp server
=====================
Credits to the author of `this <https://developer.ridgerun.com/wiki/index.php?title=Setting_Up_A_Tftp_Service>`_
guide.

.. code-block:: bash

    $ sudo apt install xinetd tftpd tftp
    $ sudo vim /etc/xinetd.d/tftp

and paste

.. code-block:: bash

    service tftp
    {
        protocol        = udp
        port            = 69
        socket_type     = dgram
        wait            = yes
        user            = nobody
        server          = /usr/sbin/in.tftpd
        server_args     = /srv/tftp
        disable         = no
    }

Save the file and exit, then create the directory and fix permissions

.. code-block:: bash

    $ sudo mkdir /srv/tftp
    $ sudo chmod -R 777 /srv/tftp
    $ sudo chown -R nobody /srv/tftp

Start tftpd through xinetd

.. code-block:: bash

    $ sudo /etc/init.d/xinetd restart

Configure xen
===========================

How to get the dtb:

qemu-system-aarch64  -machine virt,gic_version=3 -machine virtualization=true -cpu cortex-a57 -machine type=virt -m 4096 -smp 4 -display none -machine dumpdtb=virt-gicv3.dtb


Find the size of the images needed by using command below on bash prompt and replace in u-boot commands below:
printf "0x%x\n" $(stat -c %s <filename>)

fdt addr 0x44000000
fdt resize
fdt set /chosen \#address-cells <1>
fdt set /chosen \#size-cells <1>
fdt mknod /chosen module@0
fdt set /chosen/module@0 compatible "xen,linux-zimage" "xen,multiboot-module"
fdt set /chosen/module@0 reg <0x47000000 0xa5779a>
fdt set /chosen/module@0 bootargs "rw root=/dev/ram rdinit=/sbin/init console=hvc0 earlycon=xenboot"
fdt mknod /chosen module@1
fdt set /chosen/module@1 compatible "xen,linux-initrd" "xen,multiboot-module"
fdt set /chosen/module@1 reg <0x42000000 0x2fc053>
booti 0x49000000 - 0x44000000

If reboot happens after xen without linux boot, check the sizes in reg command above


Symlink the necessary files
===========================
.. code-block:: bash

    $ cd /srv/tftp
    $ ln -s <project_path>/linux/arch/arm64/boot/Image .
    $ ln -s <project_path>/linux/arch/arm64/boot/Image.gz .
    $ ln -s <project_path>/buildroot/output/images/rootfs.cpio.uboot .
    $ ln -s <project_path>/buildroot/output/images/rootfs.cpio.gz .
    $ ln -s <project_path>/out/qemu-aarch64.dtb .



// Joakim Bech
2020-11-18

