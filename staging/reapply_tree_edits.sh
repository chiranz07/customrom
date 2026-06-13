#!/usr/bin/env bash
# Re-apply the 3 Pixel 8 tree edits after a destructive `repo sync --force-sync`.
cd /home/chiranz/infinityx || exit 1
cp .staging/infinity_shiba.mk            device/google/shusky/infinity_shiba.mk
cp .staging/AndroidProducts.mk.shusky    device/google/shusky/AndroidProducts.mk
cp .staging/audio_effects_config.xml.zuma device/google/zuma/audio_effects_config.xml
echo "Re-applied: infinity_shiba.mk, AndroidProducts.mk (shusky), audio_effects_config.xml (zuma)"
grep -c jamesdsp device/google/zuma/audio_effects_config.xml
