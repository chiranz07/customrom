PRODUCT_SOONG_NAMESPACES += \
    vendor/JamesDSP

PRODUCT_PACKAGES += \
    JamesDSP \
    libjamesdspaidl \
    allowlist_james_dsp.xml

PRODUCT_COPY_FILES += \
	vendor/JamesDSP/proprietary/vendor/etc/audio_effects_config.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects_config.xml

# Sepolicy
BOARD_SEPOLICY_DIRS += vendor/JamesDSP/sepolicy
