#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#
# Mist-OS product makefile for Pixel 8 Pro (husky). See mist_shiba.mk for
# the face-unlock/JamesDSP auto-wiring note -- same applies here.

$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Minimal GMS -- see mist_shiba.mk for rationale.
WITH_GMS := true
TARGET_USES_MINI_GAPPS := true

# See mist_shiba.mk for full rationale -- Mist-OS's LINEAGE_BUILD
# auto-derivation expects a "lineage_"-prefixed product name, which our
# "mist_" naming doesn't match. Root cause of the apns-conf.xml collision.
LINEAGE_BUILD := husky

DEVICE_CODENAME := husky
DEVICE_PATH := device/google/shusky
VENDOR_PATH := vendor/google/husky
$(call inherit-product, $(DEVICE_PATH)/aosp_$(DEVICE_CODENAME).mk)

# Device identifier. Must come after all inclusions.
PRODUCT_NAME := mist_$(DEVICE_CODENAME)
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 8 Pro
PRODUCT_DEVICE := $(DEVICE_CODENAME)
PRODUCT_MANUFACTURER := Google

# Fingerprint matches the actual blob/firmware level (TheMuppets husky blobs,
# Aug 2026 SPL) -- do not spoof newer than this.
PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="husky-user 17 CP2A.260805.005 15828068 release-keys" \
    BuildFingerprint=google/husky/husky:17/CP2A.260805.005/15828068:user/release-keys \
    DeviceProduct=$(DEVICE_CODENAME)

# Mini GApps packages land in bare system/ and trip generic_system.mk's GSI
# artifact-path requirement -- same offenders as mist_shiba.mk across both
# checkers (GMS package is device-independent); verify with m nothing once
# husky is lunched too.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/apex/com.google.android.webapp.apex \
    system/lib64/libtensorflowlite_gpu_jni.so \
    system/app/GoogleExtShared/GoogleExtShared.apk \
    system/app/GooglePrintRecommendationService/GooglePrintRecommendationService.apk \
    system/priv-app/DocumentsUIGoogle/DocumentsUIGoogle.apk \
    system/priv-app/TagGoogle/TagGoogle.apk

# Same apns-conf.xml collision as mist_shiba.mk -- see there for rationale.
PRODUCT_PACKAGES := $(filter-out apns-conf.xml,$(PRODUCT_PACKAGES))
PRODUCT_COPY_FILES := $(filter-out device/sample/etc/apns-full-conf.xml:product/etc/apns-conf.xml,$(PRODUCT_COPY_FILES))

# Same zuma default-permissions.xml collision as mist_shiba.mk.
PRODUCT_COPY_FILES := $(filter-out device/google/zuma/default-permissions.xml:product/etc/default-permissions/default-permissions.xml,$(PRODUCT_COPY_FILES))

# Same DeviceIntelligenceNetworkPrebuiltAstrea collision as mist_shiba.mk --
# see there for rationale. Not yet verified against husky's own m nothing.
PRODUCT_PACKAGES := $(filter-out DeviceIntelligenceNetworkPrebuiltAstrea,$(PRODUCT_PACKAGES))

$(call inherit-product, $(VENDOR_PATH)/$(DEVICE_CODENAME)-vendor.mk)
