#!/bin/bash
# After prep: create voltage_{shiba,husky}.mk from lineage_*.mk, register, strip duplicate blob modules, launch shiba.
cd ~/voltage || exit 1
until grep -qE "PREP_DONE|DEVICE_SYNC_FAILED|MAIN_SYNC_FAILED" ~/voltage_prep.log; do sleep 60; done
grep -q PREP_DONE ~/voltage_prep.log || { echo "PREP_FAILED $(date)"; exit 1; }
cd device/google/shusky || exit 1
for d in shiba husky; do
  sed -e 's#vendor/lineage/config/common_full_phone.mk#vendor/voltage/config/common_full_phone.mk#' \
      -e "s#^PRODUCT_NAME := lineage_\$(DEVICE_CODENAME)#PRODUCT_NAME := voltage_\$(DEVICE_CODENAME)#" lineage_$d.mk > voltage_$d.mk
  cat >> voltage_$d.mk <<'M'

# VoltageOS additions (Pixel 8 family on LineageOS lineage-24.0 trees)
TARGET_BOOT_ANIMATION_RES := $(TARGET_SCREEN_WIDTH)
# generic_system.mk GSI artifact-path check: allow Google/vendor bits that land in bare system/
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/apex/% system/app/% system/priv-app/% system/lib/% system/lib64/% system/etc/% \
    system/framework/% system/bin/% system/fonts/% system/media/% system/usr/%
M
  grep -q "voltage_$d.mk" AndroidProducts.mk || sed -i "s#    \$(LOCAL_DIR)/lineage_shiba.mk#    \$(LOCAL_DIR)/lineage_shiba.mk \\\\\n    \$(LOCAL_DIR)/voltage_$d.mk#" AndroidProducts.mk
done
# AndroidProducts sanity: lineage_shiba line must keep its continuation; print
sed -i 's#\$(LOCAL_DIR)/lineage_shiba.mk \\\n    \$(LOCAL_DIR)/voltage_husky.mk \\\n    \$(LOCAL_DIR)/voltage_shiba.mk#&#' AndroidProducts.mk
cat AndroidProducts.mk | grep -v "^#"
grep -n "common_full_phone\|PRODUCT_NAME\|BOOT_ANIMATION" voltage_shiba.mk
cd ~/voltage
python3 - <<'PY'
import re,glob
other=set()
for f in glob.glob("vendor/gms/**/Android.bp",recursive=True)+glob.glob("vendor/voltage/**/Android.bp",recursive=True)+glob.glob("vendor/google/pixel/**/Android.bp",recursive=True)+glob.glob("vendor/pixel/**/Android.bp",recursive=True):
    other |= set(re.findall(r'name: "([^"]+)"', open(f).read()))
for d in ("shiba","husky"):
    bpf=f"vendor/google/{d}/Android.bp"; mkf=f"vendor/google/{d}/{d}-vendor.mk"
    bp=open(bpf).read(); mk=open(mkf).read()
    dups=[n for n in re.findall(r'name: "([^"]+)"', bp) if n in other]
    print(d,"duplicates:",dups)
    for n in dups:
        bp,k=re.subn(r'\n[a-z_]+ \{\n    name: "%s",\n(?:.*\n)*?\}\n' % re.escape(n), '\n', bp, count=1)
        mk,k2=re.subn(r'^    %s \\\n' % re.escape(n), '', mk, count=1, flags=re.M)
        print("  removed",n,k,k2)
    open(bpf,"w").write(bp); open(mkf,"w").write(mk)
PY
bash ~/launch_voltage.sh shiba voltage_shiba-cp2a-userdebug bacon
echo "STAGE2_LAUNCHED $(date)"
