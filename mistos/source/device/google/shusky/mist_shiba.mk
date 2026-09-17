#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#
# Mist-OS product makefile for Pixel 8 (shiba).
# device/google/shusky ships only aosp_shiba.mk / lineage_shiba.mk -- this
# adds the mist_shiba lunch target the same way, cloning aosp_shiba.mk.
#
# Google face-unlock and JamesDSP are NOT inherited here -- zuma/common.mk
# already has inherit-product-if-exists hooks for vendor/google/faceunlock/config.mk
# and vendor/JamesDSP/config.mk, and both projects are pulled by our local
# manifest at exactly those paths. Auto-wired, nothing to add.

# Plain (non-PRODUCT_*) variables set anywhere in this file are visible to
# every inherited makefile: inherit-product only RECORDS the parent path, and
# the build parses this whole file first, then the parents. (That same
# ordering is why a PRODUCT_PACKAGES filter-out in this file can never remove
# something a parent adds: the parent's += happens after we've been parsed.)
MISTOS_MAINTAINER := chiranz

# Quick Tap (back double-tap). vendor/gms/gms_mini.mk defaults this to
# `?= false` (gms_full/pico default it to true), which silently dropped
# ColumbusService (vendor/lineage/config/mist.mk gates on it) and the
# quick_tap sysconfig. Pixel 8 has the real Columbus CHRE nanoapp in the
# blobs (vendor/etc/chre/columbus.so, appId 0x476f6f676c001019, the exact
# ID ColumbusService's CHRESensor talks to) plus android.hardware.context_hub,
# so the CHRE path is used, no AP-sensor tflite model needed.
TARGET_SUPPORTS_QUICK_TAP := true

$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Minimal GMS: Play Store + Play Services core, not the full bundled-apps
# package (Photos/YouTube/Maps/etc). Real Pixel features (Now Playing,
# face-unlock enroll UI, Clear Calling toggle) come from TheMuppets' blobs
# and the face-unlock/pixel-framework projects, not from the GApps package
# itself, so mini is enough -- no need for the full package's bloat.
WITH_GMS := true
TARGET_USES_MINI_GAPPS := true

# Mist-OS's own tooling (mistify()) always lunches lineage_<device>, never a
# custom-prefixed product -- LINEAGE_BUILD auto-derives from that "lineage_"
# prefix somewhere in the base chain, which our "mist_" naming never matches.
# Root cause of the apns-conf.xml collision: build/make/target/product/
# aosp_product.mk only adds its (colliding) generic APN copy rule
# `ifeq ($(LINEAGE_BUILD),)` -- i.e. only when this is unset. Setting it
# explicitly suppresses that path entirely -- the actual fix. The earlier
# PRODUCT_COPY_FILES filter-out (still left in above) apparently ran at the
# wrong point in the inherit chain to catch it; not worth chasing further
# under time pressure now that the real root cause is addressed here.
LINEAGE_BUILD := shiba

DEVICE_CODENAME := shiba
DEVICE_PATH := device/google/shusky
VENDOR_PATH := vendor/google/shiba
$(call inherit-product, $(DEVICE_PATH)/aosp_$(DEVICE_CODENAME).mk)

# Mist "About phone" hardware card props (ro.mist.soc/battery/display/...).
# A .prop file, not PRODUCT_PRODUCT_PROPERTIES: those split on spaces.
TARGET_PRODUCT_PROP += $(DEVICE_PATH)/$(DEVICE_CODENAME)/mist_about.prop

# Device identifier. Must come after all inclusions.
PRODUCT_NAME := mist_$(DEVICE_CODENAME)
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 8
PRODUCT_DEVICE := $(DEVICE_CODENAME)
PRODUCT_MANUFACTURER := Google

# Fingerprint matches the actual blob/firmware level (TheMuppets shiba blobs,
# Aug 2026 SPL) -- do not spoof newer than this, it breaks Play Integrity's
# claimed-vs-attested check rather than helping it.
PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="shiba-user 17 CP2A.260805.005 15828068 release-keys" \
    BuildFingerprint=google/shiba/shiba:17/CP2A.260805.005/15828068:user/release-keys \
    DeviceProduct=$(DEVICE_CODENAME)

# Mini GApps packages land in bare system/ and trip generic_system.mk's GSI
# artifact-path requirement. TWO separate checkers (soong analysis, then
# kati/make) each report their own offender set -- both caught by m nothing,
# not guessed, on separate build passes.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/apex/com.google.android.webapp.apex \
    system/lib64/libtensorflowlite_gpu_jni.so \
    system/app/GoogleExtShared/GoogleExtShared.apk \
    system/app/GooglePrintRecommendationService/GooglePrintRecommendationService.apk \
    system/priv-app/DocumentsUIGoogle/DocumentsUIGoogle.apk \
    system/priv-app/TagGoogle/TagGoogle.apk

# Two sources both write to product/etc/apns-conf.xml: Mist's own vendor/apn
# Soong module (pulled via telephony.mk's PRODUCT_PACKAGES), and a generic
# AOSP PRODUCT_COPY_FILES entry from device/sample/etc/apns-full-conf.xml
# inherited somewhere in the base chain. Confirmed the second one via
# `get_build_var PRODUCT_COPY_FILES | grep apns` -- filtering PRODUCT_PACKAGES
# alone didn't help since that's not where this entry comes from. GMS/vendor
# blobs already carry real Google carrier-config data (CarrierSettings,
# CarrierLocation, CarrierMetrics, onecall_no.pb in TheMuppets' blobs), so
# dropping the generic AOSP fallback costs nothing functional.
PRODUCT_PACKAGES := $(filter-out apns-conf.xml,$(PRODUCT_PACKAGES))
PRODUCT_COPY_FILES := $(filter-out device/sample/etc/apns-full-conf.xml:product/etc/apns-conf.xml,$(PRODUCT_COPY_FILES))

# zuma's own default-permissions.xml collides with Mist-OS's own (Soong,
# ROM-wide baseline) version at the same destination. Dropping zuma's --
# lower risk than merging two permission-grant XML files blindly under time
# pressure; worst case is some Pixel-specific app needs a runtime permission
# grant instead of a default one, not a functional break.
PRODUCT_COPY_FILES := $(filter-out device/google/zuma/default-permissions.xml:product/etc/default-permissions/default-permissions.xml,$(PRODUCT_COPY_FILES))

# DeviceIntelligenceNetworkPrebuiltAstrea: mini-gapps' generic package
# collides by LOCAL_MODULE name with the real one already provided by
# vendor/google/shiba's blobs. NOTE: filtering PRODUCT_PACKAGES alone does
# NOT fix this -- kati globs and registers every Android.mk it finds
# regardless of PRODUCT_PACKAGES membership, so the actual fix is renaming
# vendor/gms's competing package directory out of discovery:
# vendor/gms/product/packages/privileged_apps/DeviceIntelligenceNetworkPrebuiltAstrea
# is renamed to ...Astrea.disabled (and its Android.mk to Android.mk.disabled).
# The real TheMuppets copy (vendor/google/shiba/Android.bp) is what ships.
# Left this filter in as harmless belt-and-suspenders.
PRODUCT_PACKAGES := $(filter-out DeviceIntelligenceNetworkPrebuiltAstrea,$(PRODUCT_PACKAGES))

# AOSP's base_product.mk and hardware/google/pixel/common/pixel-common-device.mk
# both unconditionally add the generic/emulator "virtual" biometrics HAL
# modules (meant for CTS/VTS and Cuttlefish, not real hardware). Shipping them
# alongside the real Goodix fingerprint HAL and Google's real face-unlock HAL
# causes an AIDL instance conflict -- fingerprint disappears from Settings
# entirely, and the fake virtual face HAL gets used instead of real Pixel
# Face Unlock. NOTE: this filter alone does NOT actually remove them (same
# category as the Astrea case above) -- the real fix is deleting the two
# PRODUCT_PACKAGES += lines directly in those two source files. Left this
# filter in as harmless belt-and-suspenders.
PRODUCT_PACKAGES := $(filter-out \
    com.android.hardware.biometrics.fingerprint.virtual \
    com.android.hardware.biometrics.face.virtual, \
    $(PRODUCT_PACKAGES))

# vendor/lineage/config/mist.mk unconditionally ships Mist-OS's own generic
# co.aospa.sense (Paranoid Android "Sense", Megvii-SDK-based) software face
# unlock as "FaceUnlock", and sets ro.face.sense_service=true, which our
# patched FaceService reads to register SenseProvider as THE face provider,
# never even constructing a FaceProvider for the real Google/Pixel HAL --
# confirmed on-device via dumpsys face showing provider: SenseProvider at
# sensorId 1008 (BIOMETRIC_WEAK) while the real HAL sat fully registered and
# unused (0 log lines post-boot, getSensorProps() never called). This also
# statically overrides Settings' own config_face_enroll resource back to
# Sense's enrollment activity via FaceUnlockOverlay.apk (an immutable static
# RRO -- can't be disabled at runtime, has to not exist). Removing
# "FaceUnlock" here cascades via its own `required` list in
# packages/apps/FaceUnlock/Android.bp to also drop FaceUnlockOverlay, its
# auto-generated product RRO, and all co.aospa.sense support files, since
# Soong only installs `required` modules when the requiring module itself
# is installed. FaceEnrollOverlay.apk (targets the *Google* enroll app, not
# Settings) is unaffected and still needed.
PRODUCT_PACKAGES := $(filter-out FaceUnlock,$(PRODUCT_PACKAGES))
PRODUCT_SYSTEM_EXT_PROPERTIES := $(filter-out ro.face.sense_service=true,$(PRODUCT_SYSTEM_EXT_PROPERTIES))

$(call inherit-product, $(VENDOR_PATH)/$(DEVICE_CODENAME)-vendor.mk)
