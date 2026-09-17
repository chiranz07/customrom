#
# Copyright (C) 2018-2019 The Google Pixel3ROM Project
# Copyright (C) 2024 The hentaiOS Project and its Proprietors
#
# Licensed under the Apache License, Version 2.0 (the License);
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an AS IS BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#

# APEX
DISABLE_DEXPREOPT_CHECK := true

PRODUCT_PACKAGES += \
    com.google.android.gmssystem.prodvic

# Quick Tap
TARGET_SUPPORTS_QUICK_TAP ?= false
ifeq ($(TARGET_SUPPORTS_QUICK_TAP),true)
PRODUCT_PACKAGES += \
    quick_tap
endif

# product/app
PRODUCT_PACKAGES += \
    CalculatorGooglePrebuilt_85006267 \
    CalendarGooglePrebuilt \
    Chrome \
    Chrome-Stub \
    GoogleContacts \
    GoogleTTS \
    LatinIMEGooglePrebuilt \
    LocationHistoryPrebuilt \
    MarkupGoogle_v2 \
    PixelThemesStub2025 \
    SoundPickerPrebuilt_33000242 \
    TrichromeLibrary \
    TrichromeLibrary-Stub \
    WebViewGoogle \
    WebViewGoogle-Stub \
    talkback

TARGET_INCLUDE_LIVE_WALLPAPERS ?= false
ifeq ($(TARGET_INCLUDE_LIVE_WALLPAPERS),true)
PRODUCT_PACKAGES += \
    PixelWallpapers2025
endif

TARGET_INCLUDE_STOCK_ARCORE ?= false
ifeq ($(TARGET_INCLUDE_STOCK_ARCORE),true)
PRODUCT_PACKAGES += \
    arcore-1.48
endif

# product/priv-app
# Velvet (Google Search/Assistant) is required here even in the minimal
# GMS variant -- NexusLauncherRelease's own Settings screen
# (MySettingsFragment.initPreference, "search_settings" key) calls
# OSEInfo.getOverlayPackage().equals(OSEInfo.pkg) with no null check, and
# getOverlayPackage() returns null when no search-overlay app is
# installed, crashing Pixel Launcher's Settings with an NPE every time
# it's opened. Confirmed via smali decompile of the built APK. Without
# Velvet there is no way to open Home settings at all.
# GoogleRestorePrebuilt (com.google.android.apps.restore, Pixel's "Data
# Restore Tool"/Migrate) is queried directly by SetupWizard during first
# boot (settingscard content provider) even when not doing a phone-to-phone
# migration -- without it SetupWizard throws Unknown authority /
# SecurityException on every boot. Self-contained prebuilt, no deps.
PRODUCT_PACKAGES += \
    AndroidAutoStubPrebuilt \
    CarrierLocation \
    ConfigUpdater \
    GoogleDialer \
    GoogleRestorePrebuilt-v1007163 \
    PrebuiltDeskClockGoogle_76042511 \
    PrebuiltPixelCoreServices \
    SettingsIntelligenceGooglePrebuilt \
    SetupWizardPrebuilt_versioned \
    Phonesky \
    Velvet \
    VerifierPrebuiltClassic

# system/app
PRODUCT_PACKAGES += \
    GoogleExtShared \
    GooglePrintRecommendationService

# system/priv-app
PRODUCT_PACKAGES += \
    DocumentsUIGoogle \
    TagGoogle

# system_ext/priv-app
PRODUCT_PACKAGES += \
    GoogleServicesFramework \
    NexusLauncherRelease \
    SetupWizardPixelPrebuilt_versioned \
    WallpaperPickerGoogleRelease

# PrebuiltGmsCore
PRODUCT_PACKAGES += \
    PrebuiltGmsCoreVic_AdsDynamite \
    PrebuiltGmsCoreVic_CronetDynamite \
    PrebuiltGmsCoreVic_DynamiteLoader \
    PrebuiltGmsCoreVic_DynamiteModulesA \
    PrebuiltGmsCoreVic_DynamiteModulesC \
    PrebuiltGmsCoreVic_GoogleCertificates \
    PrebuiltGmsCoreVic_MapsDynamite \
    PrebuiltGmsCoreVic_MeasurementDynamite \
    AndroidPlatformServices \
    MlkitBarcodeUIPrebuilt \
    SpoonPcPrebuilt \
    TfliteDynamitePrebuilt \
    VisionBarcodePrebuilt

$(call inherit-product, vendor/gms/product/blobs/product_blobs.mk)
$(call inherit-product, vendor/gms/system/blobs/system_blobs.mk)
$(call inherit-product, vendor/gms/system_ext/blobs/system-ext_blobs.mk)
