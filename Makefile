# Todo
# 3. Enable ordinary boot w/o tftp
# 6. Run Image and/or Image.gz
# 8. Load and pass QEMU DTB
# 9. Modify DTB
# 10. Create boot.scr or uboot.env

################################################################################
# Paths to git projects and various binaries
################################################################################
CCACHE ?= $(shell which ccache) # Don't remove this comment (space is needed)

ROOT				?= $(PWD)/..

BUILD_PATH			?= $(ROOT)/build
BR_PATH				?= $(ROOT)/buildroot
LINUX_PATH			?= $(ROOT)/linux
OUT_PATH			?= $(ROOT)/out
QEMU_PATH			?= $(ROOT)/qemu
UBOOT_PATH			?= $(ROOT)/u-boot
MKIMAGE_PATH			?= $(UBOOT_PATH)/tools
XEN_PATH			?= $(ROOT)/xen

DEBUG				?= n
PLATFORM			?= qemu

# Binaries
BIOS				?= $(UBOOT_PATH)/u-boot.bin
CONFIG_FRAGMENT			?= $(BUILD_PATH)/.config-fragment
KERNEL				?= $(LINUX_PATH)/arch/arm64/boot/Image
KERNELZ				?= $(LINUX_PATH)/arch/arm64/boot/Image.gz
KERNEL_UIMAGE			?= $(OUT_PATH)/uImage
LINUX_VMLINUX			?= $(LINUX_PATH)/vmlinux
QEMU_BIN			?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
QEMU_DTB			?= $(OUT_PATH)/qemu-aarch64.dtb
QEMU_ENV			?= $(OUT_PATH)/envstore.img
ROOTFS				?= $(BR_PATH)/output/images/rootfs.cpio.gz
UROOTFS				?= $(BR_PATH)/output/images/rootfs.cpio.uboot
XEN				?= $(XEN_PATH)/xen

################################################################################
# Targets
################################################################################
.PHONY: all
all: linux qemu uboot buildroot xen uboot-images

include toolchain.mk

#################################################################################
## Buildroot
##		BR2_CCACHE_DIR="$(CCACHE_DIR)" && \
#################################################################################
BR_DEFCONFIG_FILES := $(BUILD_PATH)/br_kconfigs/br_qemu_aarch64_virt.conf
$(BR_PATH)/.config:
	cd $(BR_PATH) && \
	support/kconfig/merge_config.sh \
	$(BR_DEFCONFIG_FILES)

# Note that the AARCH64_PATH here is necessary and it's used in the
# br_kconfigs/br_qemu_aarch64_virt.conf file where a variable is used to find
# and set the # correct toolchain to use.
.PHONY: buildroot
buildroot: $(BR_PATH)/.config
	$(MAKE) -C $(BR_PATH) \
		AARCH64_PATH=$(AARCH64_PATH) &&\
	ln -sf $(ROOTFS) $(OUT_PATH)/ && \
	ln -sf $(UROOTFS) $(OUT_PATH)/

.PHONY: buildroot-clean
buildroot-clean:
	cd $(BR_PATH) && git clean -xdf

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_FILES := $(LINUX_PATH)/arch/arm64/configs/defconfig


$(LINUX_PATH)/.config: $(LINUX_DEFCONFIG_FILES)
	cd $(LINUX_PATH) && \
                ARCH=arm64 \
                scripts/kconfig/merge_config.sh $(LINUX_DEFCONFIG_FILES)

.PHONY: linux-defconfig
linux-defconfig: $(LINUX_PATH)/.config

.PHONY: linux
linux: linux-defconfig
	yes | $(MAKE) -C $(LINUX_PATH) \
		ARCH=arm64 CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		Image.gz dtbs && \
	ln -sf $(KERNEL) $(OUT_PATH)/ && \
	ln -sf $(KERNELZ) $(OUT_PATH)/

.PHONY: linux-menuconfig
linux-menuconfig: $(LINUX_PATH)/.config
	$(MAKE) -C $(LINUX_PATH) ARCH=arm64 menuconfig

.PHONY: linux-clean
linux-clean:
	cd $(LINUX_PATH) && git clean -xdf

.PHONY: linux-cscope
linux-cscope:
	$(MAKE) -C $(LINUX_PATH) cscope

################################################################################
# XEN
################################################################################
.PHONY: xen
xen: 
	make -C $(XEN_PATH) \
		dist-xen XEN_TARGET_ARCH=arm64 \
	       	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		ln -sf $(XEN)/xen $(OUT_PATH)

################################################################################
# QEMU
################################################################################
qemu-configure:
	cd $(QEMU_PATH) && \
	./configure --target-list=aarch64-softmmu \
		--cc="$(CCACHE)gcc" \
		--extra-cflags="-Wno-error" \
		--enable-virtfs

.PHONY: qemu
qemu: qemu-configure
	make -C $(QEMU_PATH)

.PHONY: qemu-clean
qemu-clean:
	cd $(QEMU_PATH) && git clean -xdf

dump-dtb:
	$(QEMU_BIN) -machine virt \
		-cpu cortex-a57 \
		-machine dumpdtb=$(QEMU_DTB)

create-env-image:
	@if [ ! -f $(QEMU_ENV) ]; then \
		echo "Creating envstore image ..."; \
		qemu-img create -f raw $(QEMU_ENV) 64M; \
	fi

################################################################################
# mkimage
################################################################################
uboot-images: uimage urootfs

KERNEL_ENTRY	?= 0x40400000
KERNEL_LOADADDR ?= 0x40400000
ROOTFS_ENTRY	?= 0x44000000
ROOTFS_LOADADDR ?= 0x44000000

# TODO: The linux.bin thing probably isn't necessary.
.PHONY: uimage
uimage: $(KERNEL)
	mkdir -p $(OUT_PATH) && \
	${AARCH64_CROSS_COMPILE}objcopy -O binary -R .note -R .comment -S $(LINUX_PATH)/vmlinux $(OUT_PATH)/linux.bin && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-O linux \
				-T kernel \
				-C none \
				-a $(KERNEL_LOADADDR) \
				-e $(KERNEL_ENTRY) \
				-n "Linux kernel" \
				-d $(OUT_PATH)/linux.bin $(KERNEL_UIMAGE)

# FIXME: Names clashes ROOTFS and UROOTFS, this will overwrite the u-rootfs from Buildroot.
.PHONY: urootfs
urootfs:
	mkdir -p $(OUT_PATH) && \
	$(MKIMAGE_PATH)/mkimage -A arm64 \
				-T ramdisk \
				-C gzip \
				-a $(ROOTFS_LOADADDR) \
				-e $(ROOTFS_ENTRY) \
				-n "Root files system" \
				-d $(ROOTFS) $(UROOTFS)


################################################################################
# U-boot
################################################################################
UBOOT_DEFCONFIG_FILES := $(UBOOT_PATH)/configs/qemu_arm64_defconfig

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

.PHONY: uboot-defconfig
uboot-defconfig: $(UBOOT_PATH)/.config

.PHONY: uboot
uboot: uboot-defconfig
	mkdir -p $(OUT_PATH) && \
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" && \
	ln -sf $(BIOS) $(OUT_PATH)/

.PHONY: uboot-menuconfig
uboot-menuconfig: uboot-defconfig
	$(MAKE) -C $(UBOOT_PATH) \
		CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		menuconfig

.PHONY: uboot-clean
uboot-clean:
	cd $(UBOOT_PATH) && git clean -xdf

.PHONY: uboot-cscope
uboot-cscope:
	$(MAKE) -C $(UBOOT_PATH) cscope

################################################################################
# Run targets
################################################################################
QEMU_BIOS	?= -bios u-boot.bin
QEMU_KERNEL	?= -kernel Image.gz

QEMU_ARGS	+= -nographic \
		   -smp 4 \
		   -serial tcp:localhost:54320 \
		   -machine virt,gic-version=3 \
		   -cpu cortex-a57 \
		   -d unimp \
		   -m 4096 \
		   -no-acpi

QEMU_XEN	+= -machine virtualization=true \
		   -device loader,file=xen,force-raw=on,addr=0x49000000 \
		   -device loader,file=Image.gz,addr=0x47000000  \
		   -device loader,file=rootfs.cpio.gz,addr=0x42000000	\
		   -device loader,file=virt-gicv3.dtb,addr=0x44000000

ifeq ($(GDB),y)
QEMU_ARGS	+= -s -S

# For convenience, setup path to gdb
$(shell ln -sf $(AARCH64_PATH)/bin/aarch64-none-linux-gnu-gdb $(ROOT)/gdb)
endif

# Target to run U-boot and Linux kernel where U-boot is the bios and the kernel
# is pulled from the block device.
.PHONY: run
run: create-env-image
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_XEN) \
		$(QEMU_BIOS) \
		-semihosting-config enable,target=native \
                -append 'console=ttyAMA0,38400 keep_bootcon root=/dev/vda2'


# Target to run U-boot and Linux kernel where U-boot is the bios and the kernel
# is pulled from tftp.
#
# To then boot using DHCP do:
#  setenv serverip <host-computer-ip>
#  tftp 0x40400000 uImage
.PHONY: run-netboot
run-netboot: create-env-image uimage
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_BIOS) \
		$(QEMU_XEN) \
		-netdev user,id=vmnic -device virtio-net-device,netdev=vmnic \
		-drive if=pflash,format=raw,index=1,file=envstore.img

# Target to run just Linux kernel directly. Here it's expected that the root fs
# has been compiled into the kernel itself.
.PHONY: run-kernel
run-kernel:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
                -append "console=ttyAMA0"

# Target to run just Linux kernel directly and pulling the root fs separately.
.PHONY: run-kernel-initrd
run-kernel-initrd:
	cd $(OUT_PATH) && \
	$(QEMU_BIN) \
		$(QEMU_ARGS) \
		$(QEMU_KERNEL) \
		-initrd $(ROOTFS) \
                -append "console=ttyAMA0"


################################################################################
# Clean
################################################################################
.PHONY: clean
clean: buildroot-clean linux-clean qemu-clean uboot-clean

.PHONY: distclean
distclean: clean
	rm -rf $(OUT_PATH)
