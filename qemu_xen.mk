################################################################################
# Following variables defines how the NS_USER (Non Secure User - Client
# Application), NS_KERNEL (Non Secure Kernel), S_KERNEL (Secure Kernel) and
# S_USER (Secure User - TA) are compiled
################################################################################
COMPILE_NS_USER ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER ?= 64
COMPILE_S_KERNEL ?= 64

################################################################################
# If you change this, you MUST run `make arm-tf-clean` first before rebuilding
################################################################################
TF_A_TRUSTED_BOARD_BOOT ?= n

BR2_ROOTFS_OVERLAY = $(ROOT)/build/br-ext/board/qemu/overlay
BR2_ROOTFS_POST_BUILD_SCRIPT = $(ROOT)/build/br-ext/board/qemu/post-build.sh
BR2_ROOTFS_POST_SCRIPT_ARGS = "$(QEMU_VIRTFS_AUTOMOUNT) $(QEMU_VIRTFS_MOUNTPOINT) $(QEMU_PSS_AUTOMOUNT)"

OPTEE_OS_PLATFORM = vexpress-qemu_armv8a

include common.mk

DEBUG ?= 1

# Bu default QEMU works only with GICv3 for vitualization
GICV3 ?= y

# If things go wrong , we can try booting from uboot as bios
BIOS_UBOOT ?= n

################################################################################
# Paths to git projects and various binaries
################################################################################
TF_A_PATH		?= $(ROOT)/trusted-firmware-a
BINARIES_PATH		?= $(ROOT)/out/bin
EDK2_PATH		?= $(ROOT)/edk2
EDK2_TOOLCHAIN		?= GCC49
EDK2_ARCH		?= AARCH64
ifeq ($(DEBUG),1)
EDK2_BUILD		?= DEBUG
else
EDK2_BUILD		?= RELEASE
endif
EDK2_BIN		?= $(EDK2_PATH)/Build/ArmVirtQemuKernel-$(EDK2_ARCH)/$(EDK2_BUILD)_$(EDK2_TOOLCHAIN)/FV/QEMU_EFI.fd
QEMU_PATH		?= $(ROOT)/qemu
QEMU_BIN		?= $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64
SOC_TERM_PATH		?= $(ROOT)/soc_term
UBOOT_PATH		?= $(ROOT)/u-boot
UBOOT_BIN		?= $(UBOOT_PATH)/u-boot.bin
XEN_PATH		?= $(ROOT)/xen
XEN			?= $(XEN_PATH)/xen
BL33_BIN		?= $(UBOOT_BIN)
#BL33_BIN		?= $(EDK2_BIN)


XEN_IMAGE		?= $(XEN_PATH)/xen/xen.efi
XEN_EXT4		?= $(BINARIES_PATH)/xen.ext4
XEN_CFG			?= $(ROOT)/build/xen.cfg
XEN_DTB			?= $(ROOT)/build/xen.dtb
KERNEL_IMAGE		?= $(LINUX_PATH)/arch/arm64/boot/Image
MKIMAGE_PATH		?= $(UBOOT_PATH)/tools
KERNEL_UIMAGE		?= $(BINARIES_PATH)/uImage
ROOTFS			?= $(BINARIES_PATH)/rootfs.cpio.gz
UROOTFS			?= $(BINARIES_PATH)/rootfs.cpio.uboot

ifeq ($(GICV3),n)
	TFA_GIC_DRIVER	?= QEMU_GICV2
	QEMU_GIC_VERSION = 2

else
	TFA_GIC_DRIVER	?= QEMU_GICV3
	QEMU_GIC_VERSION = 3
endif

ifeq ($(BIOS_UBOOT),y)
	QEMU_DTB		?= virt-gicv3.dtb
else
	QEMU_DTB		?= virt-gicv3-secure.dtb
endif
	
################################################################################
# Targets
################################################################################
all: arm-tf buildroot uboot linux optee-os qemu soc-term xen xen-create-image uboot-images dump-dtb
clean: arm-tf-clean buildroot-clean edk2-clean linux-clean optee-os-clean \
	qemu-clean soc-term-clean check-clean

include toolchain.mk

################################################################################
# ARM Trusted Firmware
################################################################################
TF_A_EXPORTS ?= \
	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"

TF_A_DEBUG ?= $(DEBUG)
ifeq ($(TF_A_DEBUG),0)
TF_A_LOGLVL ?= 30
TF_A_OUT = $(TF_A_PATH)/build/qemu/release
else
TF_A_LOGLVL ?= 50
TF_A_OUT = $(TF_A_PATH)/build/qemu/debug
endif

TF_A_FLAGS ?= \
	BL33=$(BL33_BIN) \
	PLAT=qemu \
	ARM_TSP_RAM_LOCATION=tdram \
	QEMU_USE_GIC_DRIVER=$(TFA_GIC_DRIVER) \
	DEBUG=$(TF_A_DEBUG) \
	BL32=$(OPTEE_OS_HEADER_V2_BIN) \
	BL32_EXTRA1=$(OPTEE_OS_PAGER_V2_BIN) \
	BL32_EXTRA2=$(OPTEE_OS_PAGEABLE_V2_BIN) \
	SPD=opteed \
	BL32_RAM_LOCATION=tdram \
	LOG_LEVEL=$(TF_A_LOGLVL)

ifeq ($(TF_A_TRUSTED_BOARD_BOOT),y)
TF_A_FLAGS += \
	MBEDTLS_DIR=$(ROOT)/mbedtls \
	TRUSTED_BOARD_BOOT=1 \
	GENERATE_COT=1
endif

arm-tf: optee-os uboot
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) all fip
	mkdir -p $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/bl1.bin $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/bl2.bin $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/bl31.bin $(BINARIES_PATH)
ifeq ($(TF_A_TRUSTED_BOARD_BOOT),y)
	ln -sf $(TF_A_OUT)/trusted_key.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/tos_fw_key.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/tos_fw_content.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/tb_fw.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/soc_fw_key.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/soc_fw_content.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/nt_fw_key.crt $(BINARIES_PATH)
	ln -sf $(TF_A_OUT)/nt_fw_content.crt $(BINARIES_PATH)
endif
	ln -sf $(OPTEE_OS_HEADER_V2_BIN) $(BINARIES_PATH)/bl32.bin
	ln -sf $(OPTEE_OS_PAGER_V2_BIN) $(BINARIES_PATH)/bl32_extra1.bin
	ln -sf $(OPTEE_OS_PAGEABLE_V2_BIN) $(BINARIES_PATH)/bl32_extra2.bin
	ln -sf $(BL33_BIN) $(BINARIES_PATH)/bl33.bin

arm-tf-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean

################################################################################
# QEMU
################################################################################
qemu:
	cd $(QEMU_PATH); ./configure --target-list=aarch64-softmmu\
			$(QEMU_CONFIGURE_PARAMS_COMMON)
	$(MAKE) -C $(QEMU_PATH)

qemu-clean:
	$(MAKE) -C $(QEMU_PATH) distclean


################################################################################
# EDK2 / Tianocore
################################################################################
define edk2-env
	export WORKSPACE=$(EDK2_PATH)
endef

define edk2-call
        $(EDK2_TOOLCHAIN)_$(EDK2_ARCH)_PREFIX=$(AARCH64_CROSS_COMPILE) \
        build -n `getconf _NPROCESSORS_ONLN` -a $(EDK2_ARCH) \
                -t $(EDK2_TOOLCHAIN) -p ArmVirtPkg/ArmVirtQemuKernel.dsc \
		-b $(EDK2_BUILD)
endef

edk2: edk2-common

edk2-clean: edk2-clean-common

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH := arm64
LINUX_DEFCONFIG_COMMON_FILES := \
		$(LINUX_PATH)/arch/arm64/configs/defconfig \
		$(CURDIR)/kconfigs/qemu.conf

linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64 Image Image.gz

linux: linux-common
	mkdir -p $(BINARIES_PATH)
	ln -sf $(LINUX_PATH)/arch/arm64/boot/Image $(BINARIES_PATH)
	ln -sf $(LINUX_PATH)/arch/arm64/boot/Image.gz $(BINARIES_PATH)

linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_COMMON_FLAGS += DEBUG=$(DEBUG) CFG_ARM_GICV3=$(GICV3) CFG_VIRTUALIZATION=y CFG_CORE_ASLR=y CFG_TA_ASLR=y CFG_CORE_DYN_SHM=y
optee-os: optee-os-common

optee-os-clean: optee-os-clean-common

################################################################################
# Soc-term
################################################################################
soc-term:
	$(MAKE) -C $(SOC_TERM_PATH)

soc-term-clean:
	$(MAKE) -C $(SOC_TERM_PATH) clean

################################################################################
# U-boot
################################################################################
ifeq ($(BIOS_UBOOT),y)
UBOOT_DEFCONFIG_FILES := $(UBOOT_PATH)/configs/qemu_arm64_defconfig		\
			 $(ROOT)/build/kconfigs/u-boot_qemu_virt_v8_xen_standalone.conf
BIOS		:= u-boot.bin
else
UBOOT_DEFCONFIG_FILES := $(UBOOT_PATH)/configs/qemu_arm64_defconfig		\
			 $(ROOT)/build/kconfigs/u-boot_qemu_virt_v8.conf
endif

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

.PHONY: uboot-defconfig
uboot-defconfig: $(UBOOT_PATH)/.config

.PHONY: uboot
uboot: uboot-defconfig
	$(MAKE) -C $(UBOOT_PATH) CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"
ifeq ($(BIOS_UBOOT),y)
	mkdir -p $(BINARIES_PATH)
	ln -sf $(UBOOT_PATH)/$(BIOS) $(BINARIES_PATH)/
endif	

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
# XEN
################################################################################
.PHONY: xen
xen: 
	$(MAKE) -C $(XEN_PATH) \
	dist-xen XEN_TARGET_ARCH=arm64 \
      	CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)"
	ln -sf $(XEN)/xen $(BINARIES_PATH)

XEN_TMP ?= $(BINARIES_PATH)/xen_files

# When creating the image containing Linux kernel, we need to temporarily store
# the files somewhere.
$(XEN_TMP):
	mkdir -p $@

xen-create-image: $(XEN_TMP) linux xen 
	# Use a written path to avoid rm -f real host machine files (in case
	# GRUB2_TMP has been set to an empty string)
	rm -f $(BINARIES_PATH)/xen_files/*
	cp $(KERNEL_IMAGE) $(XEN_TMP)
	cp $(XEN_IMAGE) $(XEN_TMP)
	cp $(XEN_CFG) $(XEN_TMP)
	cp $(XEN_DTB) $(XEN_TMP)
	cp $(ROOT)/out-br/images/rootfs.cpio.gz $(XEN_TMP)
	virt-make-fs -t vfat $(XEN_TMP) $(XEN_EXT4)


################################################################################
# mkimage
################################################################################
uboot-images: uimage urootfs

KERNEL_ENTRY    ?= 0x47000000
KERNEL_LOADADDR ?= 0x47000000
ROOTFS_ENTRY    ?= 0x44000000
ROOTFS_LOADADDR ?= 0x44000000

# TODO: The linux.bin thing probably isn't necessary.
.PHONY: uimage
uimage: $(KERNEL_IMAGE) uboot
	mkdir -p $(BINARIES_PATH) && \
        ${AARCH64_CROSS_COMPILE}objcopy -O binary -R .note -R .comment -S $(LINUX_PATH)/vmlinux $(BINARIES_PATH)/linux.bin && \
        $(MKIMAGE_PATH)/mkimage -A arm64 \
                                -O linux \
                                -T kernel \
                                -C none \
                                -a $(KERNEL_LOADADDR) \
                                -e $(KERNEL_ENTRY) \
                                -n "Linux kernel" \
                                -d $(BINARIES_PATH)/linux.bin $(KERNEL_UIMAGE)

# FIXME: Names clashes ROOTFS and UROOTFS, this will overwrite the u-rootfs from Buildroot.
.PHONY: urootfs
urootfs: uboot
	mkdir -p $(BINARIES_PATH) && \
	ln -sf $(ROOT)/out-br/images/rootfs.cpio.gz $(BINARIES_PATH)/ && \
        $(MKIMAGE_PATH)/mkimage -A arm64 \
                                -T ramdisk \
                                -C gzip \
                                -a $(ROOTFS_LOADADDR) \
                                -e $(ROOTFS_ENTRY) \
                                -n "Root files system" \
                                -d $(ROOTFS) $(UROOTFS)


################################################################################
# Run targets
################################################################################
.PHONY: run
# This target enforces updating root fs etc
run: all
	$(MAKE) run-only

QEMU_SMP ?= 4

QEMU_KERNEL	?= -kernel Image.gz

# This u-boot should not be compiled with defconfig in build folder
#
ifeq ($(BIOS_UBOOT),y)
QEMU_BIOS	?= -bios u-boot.bin
QEMU_SECURE_FLASH ?= 
QEMU_XEN_UBOOT	?=  -no-acpi -device loader,file=xen,force-raw=on,addr=0x49000000 \
		   -device loader,file=Image.gz,addr=0x47000000  \
		   -device loader,file=rootfs.cpio.gz,addr=0x42000000	\
		   -device loader,file=$(QEMU_DTB),addr=0x44000000
else
QEMU_BIOS	?= -bios bl1.bin
QEMU_SECURE_FLASH ?= -machine virt,secure=on
QEMU_XEN_UBOOT ?=
endif


QEMU_XEN	+= -machine virtualization=true \
		   -machine virt,gic-version=$(QEMU_GIC_VERSION)	\
		   -drive if=none,file=$(XEN_EXT4),format=raw,id=hd1 \
		   -device virtio-blk-device,drive=hd1 \
		   -netdev user,id=vmnic -device virtio-net-device,netdev=vmnic 


dump-dtb:
	$(QEMU_BIN) -machine virt,gic-version=$(QEMU_GIC_VERSION) \
		-machine virtualization=true	\
		-cpu cortex-a57 \
		-m 4096 -smp $(QEMU_SMP) -display none	\
		$(QEMU_SECURE_FLASH)		\
		-machine dumpdtb=$(BINARIES_PATH)/$(QEMU_DTB)
 
.PHONY: run-only
run-only:
	ln -sf $(ROOT)/out-br/images/rootfs.cpio.gz $(BINARIES_PATH)/
	$(call check-terminal)
	$(call run-help)
	$(call launch-terminal,54320,"Normal World")
	$(call launch-terminal,54321,"Secure World")
	$(call wait-for-ports,54320,54321)
	cd $(BINARIES_PATH) && $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64 \
		-nographic \
		-serial tcp:localhost:54320 -serial tcp:localhost:54321 \
		-smp $(QEMU_SMP) \
		-s -S $(QEMU_SECURE_FLASH)\
	       	-cpu cortex-a57 			\
		-machine virt,gic-version=$(QEMU_GIC_VERSION)			\
		-d unimp -semihosting-config enable,target=native \
		-m 1057 \
		-bios bl1.bin

		#$(QEMU_EXTRA_ARGS)



.PHONY: run-xen
run-xen: dump-dtb
	$(call check-terminal)
	$(call run-help)
	$(call launch-terminal,54320,"Normal World")
	$(call launch-terminal,54321,"Secure World")
	$(call wait-for-ports,54320,54321)
	ln -sf $(ROOT)/out-br/images/rootfs.cpio.gz $(BINARIES_PATH)/
	ln -sf $(ROOT)/out-br/images/rootfs.ext4 $(BINARIES_PATH)/
	cd $(BINARIES_PATH) && $(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64 \
		-nographic \
		-serial tcp:localhost:54320 -serial tcp:localhost:54321 \
		-smp $(QEMU_SMP) \
		-s -S $(QEMU_SECURE_FLASH)\
	       	-cpu cortex-a57 			\
		-d unimp -semihosting-config enable,target=native \
		-m 1057 \
		-no-acpi	\
		$(QEMU_BIOS)			\
		$(QEMU_XEN)			\
		$(QEMU_XEN_UBOOT)

ifneq ($(filter check,$(MAKECMDGOALS)),)
CHECK_DEPS := all
endif

ifneq ($(TIMEOUT),)
check-args := --timeout $(TIMEOUT)
endif

check: $(CHECK_DEPS)
	ln -sf $(ROOT)/out-br/images/rootfs.cpio.gz $(BINARIES_PATH)/
	cd $(BINARIES_PATH) && \
		export QEMU=$(QEMU_PATH)/aarch64-softmmu/qemu-system-aarch64 && \
		export QEMU_SMP=$(QEMU_SMP) && \
		expect $(ROOT)/build/qemu-check.exp -- $(check-args) || \
		(if [ "$(DUMP_LOGS_ON_ERROR)" ]; then \
			echo "== $$PWD/serial0.log:"; \
			cat serial0.log; \
			echo "== end of $$PWD/serial0.log:"; \
			echo "== $$PWD/serial1.log:"; \
			cat serial1.log; \
			echo "== end of $$PWD/serial1.log:"; \
		fi; false)

check-only: check

check-clean:
	rm -f serial0.log serial1.log
