#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Security - must be defined before including BoardConfig-common.mk
BOOT_SECURITY_PATCH := 2026-08-05
VENDOR_SECURITY_PATCH := $(BOOT_SECURITY_PATCH)

include device/google/zuma/BoardConfig-common.mk

# Mist-OS's extra packages (KernelSU-Next+SUSFS kernel modules, JamesDSP,
# Now Playing blobs, GMS) push the dynamic partitions past Google's stock
# 500MB safety margin (BOARD_SUPER_PARTITION_ERROR_LIMIT above) even though
# the actual image still fits well within the real BOARD_SUPER_PARTITION_SIZE.
# Narrow the margin to 64MB instead of removing it outright.
BOARD_SUPER_PARTITION_ERROR_LIMIT := $(shell echo $$(($(BOARD_SUPER_PARTITION_SIZE) - 67108864)))

# Mist-OS's vendor/lineage/build/soong/Android.bp unconditionally defines
# generated_kernel_includes/prebuilt_kernel_includes Soong modules that
# reference $(KERNEL_BUILD_OUT_PREFIX) -- Soong doesn't gate on the Make-side
# TARGET_NO_KERNEL flag set above, so the variable must exist even though
# this is a GKI device that doesn't build its kernel through this legacy
# in-tree mechanism. ionutsandroidbuilds' device tree doesn't include this
# (it wasn't authored against Mist-OS's vendor/lineage build system) --
# added here rather than upstream. Caught by `m nothing`, not assumed.
#
# BoardConfigKernel.mk alone sets KERNEL_BUILD_OUT_PREFIX as a plain Make var,
# but Soong's custom lineage_generator module type reads it through a
# separate SOONG_CONFIG export mechanism (lineageVarsPlugin namespace) that
# BoardConfigSoong.mk sets up via its static EXPORT_TO_SOONG list -- which
# already includes KERNEL_BUILD_OUT_PREFIX. Must include Kernel then Soong,
# in that order, so the Make values exist before BoardConfigSoong.mk reads
# them into the namespace.
include vendor/lineage/config/BoardConfigKernel.mk
include vendor/lineage/config/BoardConfigSoong.mk

# Kernel modules
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_BLOCKLIST_FILE := $(DEVICE_PATH)/recovery/modules.blocklist.vendor_kernel_boot
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW := $(strip $(shell cat $(DEVICE_PATH)/recovery/modules.load.vendor_kernel_boot))
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD += $(BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW)
BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES += $(addprefix $(KERNEL_MODULE_DIR)/, $(notdir $(BOARD_VENDOR_KERNEL_RAMDISK_KERNEL_MODULES_LOAD_RAW)))

# SEPolicy
BOARD_VENDOR_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/vendor \
    hardware/google/pixel-sepolicy/vibrator/common \
    hardware/google/pixel-sepolicy/vibrator/cs40l26

# WiFi
include $(DEVICE_PATH)/wifi/BoardConfig-wifi.mk
