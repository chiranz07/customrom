## JamesDSP

Integrate JamesDSP in your device trees:

  Add the config to your device common trees to **`device.mk`** or **`common.mk`**:

    # JamesDSP
    $(call inherit-product, vendor/JamesDSP/config.mk)
