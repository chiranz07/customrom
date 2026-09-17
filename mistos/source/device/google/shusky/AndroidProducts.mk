#
# SPDX-FileCopyrightText: 2019 The Android Open-Source Project
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/aosp_husky.mk \
    $(LOCAL_DIR)/aosp_shiba.mk \
    $(LOCAL_DIR)/lineage_husky.mk \
    $(LOCAL_DIR)/lineage_shiba.mk \
    $(LOCAL_DIR)/mist_husky.mk \
    $(LOCAL_DIR)/mist_shiba.mk

COMMON_LUNCH_CHOICES := \
    mist_shiba-userdebug \
    mist_husky-userdebug
