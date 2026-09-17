#
# SPDX-FileCopyrightText: 2021 The Android Open-Source Project
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Kernel
TARGET_KERNEL_DIR := device/google/shusky-kernels

ifneq ($(TARGET_BOOTS_16K),true)
PRODUCT_16K_DEVELOPER_OPTION := true
endif

# Inherit from zuma
include device/google/zuma/common.mk

# Fingerprint
# etc/permissions/android.hardware.fingerprint.xml is deliberately skipped
# from the vendor blob pull (device/google/shusky/shiba/skip-files-vendor.txt)
# on the assumption AOSP provides it -- but nothing ever actually added
# AOSP's own module, so neither existed and Settings hid fingerprint
# enrollment entirely (PackageManager.hasSystemFeature(FEATURE_FINGERPRINT)
# was false). The real Goodix HAL/service/firmware are all still pulled in
# fine, this was purely the missing feature declaration.
PRODUCT_PACKAGES += \
    android.hardware.fingerprint.prebuilt.xml

# GPS
PRODUCT_PACKAGES += \
    android.hardware.sensors-V2-ndk.vendor:64

# Overlays
PRODUCT_PACKAGES += \
    FrameworkResOverlayVendorShusky \
    PixelNfcOverlayShusky \
    PixelWifiOverlay2023Shusky \
    SafetyRegulatoryInfoOverlayProductShusky

PRODUCT_PACKAGES += \
    DMServiceOverlayVendorShiba \
    FrameworkResOverlayProductShiba \
    FrameworkResOverlayVendorShiba \
    PixelDisplayServiceOverlayProductShiba \
    PixelNfcOverlayShiba \
    SettingsGoogleShibaOverlay \
    SettingsShibaOverlay \
    SystemUIGoogleOverlayVendorShiba

# ApertureOverlayShiba intentionally not shipped: vendor/google/camera's
# GoogleCamera module declares overrides: ["Aperture", "Camera2"], so its
# target package never exists and the RRO would just be inert dead weight.
# Re-add if GoogleCamera is ever dropped and Aperture comes back.

# PowerShare
include hardware/google/pixel/powershare/device.mk

# Properties
TARGET_PRODUCT_PROP += $(DEVICE_PATH)/$(DEVICE_CODENAME)/product.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/$(DEVICE_CODENAME)/vendor.prop

# Recovery
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/recovery/init.recovery.device.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.shiba.rc

PRODUCT_PACKAGES += \
    init.recovery.shiba.touch.rc

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH)

# Window extensions
$(call inherit-product, $(SRC_TARGET_DIR)/product/window_extensions.mk)
