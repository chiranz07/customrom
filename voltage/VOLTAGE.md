# VoltageOS 6.1 (branch `17`, Android 17) for Pixel 8 (shiba) and Pixel 8 Pro (husky)

Built 2026-09-18 from https://github.com/VoltageOS/manifest branch `17` (AOSP android-17.0.0_r1, manifest
"Forks for 2026-09 ASB", release config `cp2a`). shiba: `voltage-6.1-shiba-20260918-0808-UNOFFICIAL.zip`
(1.56 GB, userdebug, signed with a locally generated key set — see §4). Full build took 36 min on the 96-core
server (remote execution).

Download: SourceForge project `chiranz`, folder `voltage/shiba/` (zip + md5) and `voltage/shiba/img/`
(boot, vendor_boot, vendor_kernel_boot, dtbo). husky in `voltage/husky/` if that build finished.

**Untested on hardware at the time of writing.**

## 0. What VoltageOS is (read before flashing)

VoltageOS is a **vanilla** LineageOS-based ROM. It ships **no GApps**; instead it includes **GmsCompat**
(GrapheneOS-style sandboxed Google Play). So: no Pixel Launcher (Launcher3QuickStep instead), no Google
Camera, no GMS core, no ASI-driven Now Playing detection, no Google Face Unlock. Voltage's own FaceUnlock,
Aperture camera, Etar, Seedvault, GameSpace, ThemePicker, LMOFreeform, OmniJaws etc. are included. Google
services come either via the sandbox (install "Play Store" from the app list) or by flashing a GApps zip.
Pixel-specific Google prebuilts that TheMuppets blobs carry (e.g. NowPlayingPrebuilt) are installed but
without GMS/ASI they do nothing.

## 1. Device trees

Same set as PixelOS (VoltageOS has no shusky/zuma trees): LineageOS lineage-24.0 device/google/{shusky,zuma,
shusky-kernels} + TheMuppets proprietary_vendor_google_{shiba,husky} (lineage-24.0), via
`local_manifests/shusky.xml` (remote name `github` is free in Voltage's manifest). VoltageOS already carries its
own forks of hardware/google/{pixel,pixel-sepolicy,interfaces} (with lineage_health/touch/powershare and
rebalance_interrupts) and packages/resources/devicesettings, so nothing else had to be added.
Kernel prebuilts (stock CP2A 6.1.157) copied from the Mist tree into device/google/shusky-kernels/6.1/ as for PixelOS.
`voltage-manifest-snapshot-20260918.xml` pins every project.

## 2. Procedure

```bash
mkdir voltage && cd voltage
repo init -u https://github.com/VoltageOS/manifest.git -b 17 --git-lfs --depth=1
cp <repo>/voltage/local_manifests/shusky.xml .repo/local_manifests/
repo sync -c --no-clone-bundle --no-tags -j24 --optimized-fetch --prune --force-sync
# kernel prebuilts into device/google/shusky-kernels/6.1/, apply patches/ (§3), generate keys (§4)
source build/envsetup.sh
lunch voltage_shiba-cp2a-userdebug       # or voltage_husky-cp2a-userdebug; `breakfast shiba` = same
m bacon -j96                             # zip: out/target/product/shiba/voltage-6.1-shiba-<date>-UNOFFICIAL.zip
```

Scripts in `scripts/`: `voltage_sync.sh`, `voltage_prep.sh` (post-sync: device sync, kernel copy, Now Playing
allowlist fix, duplicate-module report), `voltage_stage2.sh` (creates voltage_*.mk, registers, strips duplicate
blob modules, launches), `voltage_keys_and_launch.sh`, `voltage_build_supervisor.sh` (args: jobs dev lunch target;
lunch errors are reported as LUNCH_FAILURE), `launch_voltage.sh`, `voltage_upload.sh`.

## 3. Changes needed (all in `patches/`, in the order they were hit)

1. **Product makefiles** (`device_google_shusky-lineage-24.0.patch`): `voltage_{shiba,husky}.mk` = copy of
   `lineage_*.mk` with `vendor/voltage/config/common_full_phone.mk` and `PRODUCT_NAME := voltage_<dev>`, plus
   `TARGET_BOOT_ANIMATION_RES` and the generic_system artifact-path allow list (`system/apex/% system/app/% …`)
   that GMS-less Voltage still needs for Google blobs in bare system/. Registered in AndroidProducts.mk.
2. **Now Playing PCS allowlist** (`device_google_zuma-lineage-24.0.patch`): same fix as Mist/PixelOS (see
   mistos/issues/MISTOS-NOWPLAYING-PCS-ASSOC.md) — relevant only if GApps are flashed on top.
3. **Signing keys required** (§4): Soong fails with 28× `depends on undefined module
   "com.android.*.certificate.override"` because `vendor/voltage/config/common.mk` includes
   `vendor/voltage-priv/keys/keys.mk` (PRODUCT_CERTIFICATE_OVERRIDES for every APEX/priv-app) but the template
   repo has no keys/Android.bp until you run `keys.sh`.
4. **System properties** (`vendor_voltage-17.patch`): generic_system.mk enforcement (Pixel trees inherit it)
   rejects `PRODUCT_SYSTEM_PROPERTIES`/`PRODUCT_SYSTEM_DEFAULT_PROPERTIES` from device/vendor makefiles. All 17
   occurrences in vendor/voltage/config/{common,common_mobile,telephony,version}.mk changed to
   `PRODUCT_SYSTEM_EXT_PROPERTIES`.
5. **apns-conf.xml installed twice** (`build_make-17.patch`): Voltage's vendor/apn Soong module (telephony.mk) and
   AOSP's `build/make/target/product/aosp_product.mk` sample copy (inherited via zuma/aosp_common.mk) both target
   product/etc/apns-conf.xml → Kati "overriding commands". A `filter-out` in the product makefile does NOT work
   (child is parsed before inherited parents add the entry); guarded the copy in aosp_product.mk with
   `ifeq ($(VOLTAGE_BUILD),)`, exactly what LineageOS does with LINEAGE_BUILD. Verified with
   `get_build_var PRODUCT_COPY_FILES`.

Not needed here (unlike PixelOS/AOSPA): apex-contributions flag (no Google mainline APEX in PRODUCT_PACKAGES),
duplicate-module stripping (no overlap with vendor/voltage), Soong ports, Qualcomm dir exclusions.

## 4. Signing keys (private — NOT in this repo)

`vendor/voltage-priv/keys` is the VoltageOS/LineageOS key template. Run `./keys.sh` inside it: generates
`Android.bp` (android_app_certificate modules) and 90 key pairs (AOSP names at 2048 bit, all `*.certificate.override`
and `gmscompat_lib` at 4096 bit, no password). The script's last step returns non-zero even on success; check
`ls *.pk8 | wc -l` = 90. `check_keys.py <out dir>` reports only Google-presigned blobs as "unknown key" — expected.
The key set generated on 2026-09-18 lived only in `~/voltage/vendor/voltage-priv/keys` on the build server;
OTA-compatible follow-up builds need those same keys. If the server is gone, generate a new set and users must
clean-flash.

## 5. Verified from the build output

- Metadata: pre-device shiba, post-build google/shiba/shiba:17/CP2A.260805.005; ro.voltage.version=VoltageOS-6.1-UNOFFICIAL, userdebug.
- Kernel in boot.img: Linux 6.1.157-android14-11-g14047afecd8b-ab16012876 (stock CP2A).
- `/product/etc/sysconfig/allowlist_com.google.android.as.xml` has no as.oss restriction.
- Installed: GmsCompat, Launcher3QuickStep, Aperture, VoltageSetupWizard, Voltage FaceUnlock, NowPlayingPrebuilt (blob).
- Not installed: Pixel Launcher, GMS core, Google Camera, extservices APEX, ParanoidSense.
