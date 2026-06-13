#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Inherit some common stuff
$(call inherit-product, vendor/infinity/config/common_full_phone.mk)

# Inherit device configuration
DEVICE_CODENAME := shiba
DEVICE_PATH := device/google/shusky
VENDOR_PATH := vendor/google/shiba
$(call inherit-product, $(DEVICE_PATH)/aosp_$(DEVICE_CODENAME).mk)

# Audio: JamesDSP (AIDL). Device tree does not pull this in, so inherit it
# explicitly here (Google face unlock is already wired via zuma/common.mk).
$(call inherit-product-if-exists, vendor/JamesDSP/config.mk)

# This device build ships a few ROM assets in the bare system/ partition that
# trip generic_system.mk's GSI artifact-path requirement, enforced by BOTH the
# soong analysis check (Android.bp modules, e.g. OmniStyle) and the kati/make
# check (copied files, e.g. bootanimation.zip). Only the ALLOWED_LIST is honored
# by both checkers (soong ignores the 'relaxed' flag), so allow each explicitly.
# APR is a GSI-compatibility lint; this is functionally inert on a device image.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/priv-app/OmniStyle/% \
    system/media/bootanimation.zip

# Device identifier. This must come after all inclusions
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 8
PRODUCT_NAME := infinity_$(DEVICE_CODENAME)

# Boot animation
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="shiba-user 16 BP4A.260205.001 14624666 release-keys" \
    BuildFingerprint=google/shiba/shiba:16/BP4A.260205.001/14624666:user/release-keys \
    DeviceProduct=$(DEVICE_CODENAME)

$(call inherit-product, $(VENDOR_PATH)/$(DEVICE_CODENAME)-vendor.mk)
