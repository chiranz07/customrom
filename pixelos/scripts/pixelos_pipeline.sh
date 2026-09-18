#!/bin/bash
# Runs after the main sync: pulls device trees, patches product mk for PixelOS, launches build.
cd ~/pixelos || exit 1
until grep -q "SYNC_OK\|SYNC_FAILED\|INIT_FAILED" ~/pixelos_sync.log; do sleep 60; done
grep -q "SYNC_OK" ~/pixelos_sync.log || { echo "MAIN_SYNC_FAILED $(date)"; exit 1; }
echo "=== device sync $(date)"
for i in 1 2 3; do
  repo sync -c --no-clone-bundle --no-tags -j5 --force-sync device/google/shusky device/google/zuma device/google/shusky-kernels vendor/google/shiba vendor/google/husky </dev/null && break
  echo "device sync retry $i"; sleep 30
done
[ -f device/google/shusky/lineage_shiba.mk ] || { echo "DEVICE_SYNC_FAILED $(date)"; exit 1; }
echo "=== patch $(date)"
for d in shiba husky; do
  f=device/google/shusky/lineage_$d.mk
  grep -q "vendor/custom/config/common_full_phone.mk" $f || sed -i 's#vendor/lineage/config/common_full_phone.mk#vendor/custom/config/common_full_phone.mk#' $f
  grep -q "^CUSTOM_BUILD" $f || sed -i "0,/^DEVICE_CODENAME := $d/s//DEVICE_CODENAME := $d\nCUSTOM_BUILD := $d/" $f
done
grep -n "common_full_phone\|CUSTOM_BUILD" device/google/shusky/lineage_shiba.mk
echo "=== launch build $(date)"
bash ~/launch_pixelos.sh
echo "PIPELINE_LAUNCHED $(date)"
