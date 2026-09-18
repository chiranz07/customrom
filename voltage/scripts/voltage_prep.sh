#!/bin/bash
# After the main sync: device trees, kernel prebuilts, Now Playing allowlist fix, duplicate-module report. Does NOT launch.
cd ~/voltage || exit 1
until grep -qE "SYNC_OK|SYNC_FAILED|INIT_FAILED" ~/voltage_sync.log; do sleep 60; done
grep -q "SYNC_OK" ~/voltage_sync.log || { echo "MAIN_SYNC_FAILED $(date)"; exit 1; }
echo "=== device sync $(date)"
for i in 1 2 3; do repo sync -c --no-clone-bundle --no-tags -j5 --force-sync device/google/shusky device/google/zuma device/google/shusky-kernels vendor/google/shiba vendor/google/husky </dev/null && break; echo "device sync retry $i"; sleep 30; done
[ -f device/google/shusky/lineage_shiba.mk ] || { echo "DEVICE_SYNC_FAILED $(date)"; exit 1; }
SRC=~/mistos/device/google/shusky-kernels; DST=device/google/shusky-kernels/6.1
cp -a $SRC/*.ko $SRC/*.dtb $SRC/Image $SRC/Image.gz $SRC/Image.lz4 $SRC/boot.img $SRC/dtbo.img $SRC/modules.builtin $SRC/modules.builtin.modinfo $DST/ && echo "kernel: $(ls $DST/*.ko | wc -l) ko"
python3 - <<'PY'
import re
f="device/google/zuma/allowlist_com.google.android.as.xml"; s=open(f).read()
new=re.sub(r'\n    <!-- AI services open-source network component can only bind back to the core package\. -->\n    <allow-association target="com\.google\.android\.as\.oss" allowed="com\.google\.android\.as" />\n    <!-- AI services open-source network component can bind to AI Core\. -->\n    <allow-association target="com\.google\.android\.as\.oss" allowed="com\.google\.android\.aicore" />\n',
 '\n    <!-- VoltageOS/Mist fix: stock does not restrict com.google.android.as.oss (PCS); the LineageOS restriction\n         breaks the split Now Playing app (com.google.android.apps.pixel.nowplaying), Gboard and TTS. -->\n', s, count=1)
print("allowlist", "patched" if new!=s else "NOT patched"); open(f,"w").write(new)
PY
python3 - <<'PY'
import re,glob
other=set()
for f in glob.glob("vendor/gms/**/Android.bp",recursive=True)+glob.glob("vendor/voltage/**/Android.bp",recursive=True)+glob.glob("vendor/google/pixel/**/Android.bp",recursive=True)+glob.glob("vendor/pixel/**/Android.bp",recursive=True):
    other |= set(re.findall(r'name: "([^"]+)"', open(f).read()))
for d in ("shiba","husky"):
    bp=open(f"vendor/google/{d}/Android.bp").read()
    dups=[n for n in re.findall(r'name: "([^"]+)"', bp) if n in other]
    print(d, "duplicates with vendor/gms|voltage|pixel:", dups)
PY
echo "PREP_DONE $(date)"
