# PixelOS (seventeen / Android 17) for Pixel 8 (shiba) and Pixel 8 Pro (husky)

Built 2026-09-18 from https://github.com/PixelOS-AOSP/android_manifest branch `seventeen`
(AOSP tag android-17.0.0_r1, release config `cp2a`). First shiba build succeeded in 26 min
on the 96-core server: `PixelOS_shiba-17.0-20260918-0417.zip` (2.7 GB, userdebug, test keys).

Download: SourceForge project `chiranz`, folder `pixelos/shiba/` (zip + md5) and
`pixelos/shiba/img/` (boot, vendor_boot, vendor_kernel_boot, dtbo).

**Untested on hardware at the time of writing.** Everything in the zip was verified from the build
output only (see "What was verified").

## 1. Why these device trees

PixelOS has no official Pixel 8 support (its `official_devices` list has only Pixel 7/7 Pro,
inactive, Android 13). PixelOS is LineageOS-based (`vendor/lineage` + `vendor/custom`), so the
current LineageOS trees drop in unchanged:

| path | repo | branch |
|---|---|---|
| device/google/shusky | LineageOS/android_device_google_shusky | lineage-24.0 (Android 17, Aug 2026) |
| device/google/zuma | LineageOS/android_device_google_zuma | lineage-24.0 |
| device/google/shusky-kernels | LineageOS/android_device_google_shusky-kernels | lineage-24.0 (module lists only, see §3.4) |
| vendor/google/shiba, vendor/google/husky | TheMuppets/proprietary_vendor_google_{shiba,husky} (GitHub) | lineage-24.0 |

These are the same upstreams the Mist-OS trees (ionutsandroidbuilds forks) come from.
`local_manifests/shusky.xml` is the exact local manifest used. `pixelos-manifest-snapshot-20260918.xml`
pins every project to the commit that was built.

## 2. Procedure (fresh machine)

```bash
mkdir pixelos && cd pixelos
repo init -u https://github.com/PixelOS-AOSP/android_manifest.git -b seventeen --git-lfs --depth=1
mkdir -p .repo/local_manifests && cp <repo>/pixelos/local_manifests/shusky.xml .repo/local_manifests/
repo sync -c --no-clone-bundle --no-tags -j24 --optimized-fetch --prune --force-sync
# apply patches/ (see §3), put kernel prebuilts in device/google/shusky-kernels/6.1/ (see §3.4)
source build/envsetup.sh
lunch lineage_shiba-cp2a-userdebug      # or lineage_husky-cp2a-userdebug
m pixelos -j96                          # zip lands in out/target/product/shiba/PixelOS_shiba-17.0-<date>.zip
```

`breakfast shiba` does the same lunch (PixelOS's vendor/lineage envsetup uses the `lineage_` prefix and
the release name from `vendor/lineage/vars/aosp_target_release`). Official PixelOS trees name products
`custom_<device>`; that only matters for their envsetup's CUSTOM_BUILD detection, which we set by hand.

Scripts in `scripts/`: `pixelos_sync.sh` (init+sync with retries), `pixelos_pipeline.sh` (post-sync
device sync + patch + launch), `pixelos_build_supervisor.sh` / `pixelos_husky_build_supervisor.sh`
(auto-retry on OOM kills, stop on real `FAILED:`), `launch_pixelos.sh`, `pixelos_upload_shiba.sh` (SFTP).

## 3. Fixes needed (all in `patches/`, each one was a real build failure, in this order)

### 3.1 Product makefile must inherit PixelOS's vendor/custom
`device/google/shusky/lineage_{shiba,husky}.mk`: `vendor/lineage/config/common_full_phone.mk` →
`vendor/custom/config/common_full_phone.mk` (which inherits the lineage one and then
`vendor/custom/config/common.mk`: GMS from vendor/pixel/gms, Pixel Launcher, ColumbusService,
TouchGestures, bootanimation, Updater, version props). Also `CUSTOM_BUILD := shiba` so
`ro.custom.device` / the version string are populated.

### 3.2 Soong: `all_apex_contributions depends on undefined module "*.google.contributions.prebuilt"`
Release config `cp2a` inherits `mainline_2026_04`, whose `RELEASE_APEX_CONTRIBUTIONS_*` flags name
Google's prebuilt mainline-module contribution modules, which exist only in Google-internal trees.
`build/make/core/product_config.mk` normally neutralises this by setting
`PRODUCT_BUILD_IGNORE_APEX_CONTRIBUTION_CONTENTS := true` **unless** `com.google.android.conscrypt`
or `com.google.android.extservices` is in PRODUCT_PACKAGES. PixelOS's GMS ships the prebuilt
`com.google.android.extservices` APEX, so the guard turned off and Soong demanded all 46 prebuilt
contribution modules. Mist never hit this because its mini GApps has no Google mainline APEX.
Fix: `PRODUCT_BUILD_IGNORE_APEX_CONTRIBUTION_CONTENTS := true` in the product makefile
(mainline modules build from source; the Google extservices APEX still installs via `overrides`).

### 3.3 Soong: module "found in multiple namespaces (vendor/google/shiba and vendor/pixel/gms/common)"
TheMuppets blobs and PixelOS's GMS both define `AICorePrebuilt-aicore_20260302.01_RC00` and
`DeviceIntelligenceNetworkPrebuiltAstrea`. Removed both from `vendor/google/{shiba,husky}/Android.bp`
and `*-vendor.mk` (PixelOS's copies are used). Detect the list generically with: names in
vendor/google/<dev>/Android.bp ∩ names in vendor/pixel/gms/common/Android.bp.

### 3.4 Kernel: `device/google/shusky-kernels/6.1/gzvm.ko missing and no known rule`
LineageOS's shusky-kernels repo carries only `modules.load` lists; LineageOS builds the kernel from
source. We ship the stock kernel instead (user policy: stock kernel, root via blu_spark later).
Copied the whole prebuilt set from the Mist tree's `device/google/shusky-kernels`
(ionutsandroidbuilds/android_device_google_shusky-kernels, 17.0, commit 4f1d0a8; stock CP2A
6.1.157-android14-11-g14047afecd8b-ab16012876) into `device/google/shusky-kernels/6.1/`: 330 `.ko`,
4 `zuma-*.dtb`, `Image`, `Image.gz`, `Image.lz4`, `boot.img`, `dtbo.img`, `modules.builtin*`.
The Lineage `vendor_kernel_boot.modules.load` list was byte-identical to Mist's, so no list changes.
`device/google/zuma/BoardConfig-common.mk` uses `BOARD_PREBUILT_BOOTIMAGE := $(TARGET_KERNEL_DIR)/boot.img`
and `KERNEL_MODULE_DIR := $(TARGET_KERNEL_DIR)` exactly like the Mist tree.
(Alternative: extract the same files from the factory image `shiba-cp2a.260605.012-factory-*.zip`.)

### 3.5 `Device makefile produces files inside generic_system.mk's artifact path requirement`
zuma's `aosp_common.mk` already sets `PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := relaxed`, but
Soong's checker still errors on GMS/ParanoidSense/Google libs in bare `system/`. Added a wholesale
`PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/apex/% system/app/% system/priv-app/%
system/lib/% system/lib64/% system/etc/% system/framework/% system/bin/% system/fonts/% system/media/% system/usr/%`
to the product makefiles. (Mist needed the same idea with an explicit file list; there are two
checkers, Soong then kati, so a glob list avoids a second round.)

## 4. What was verified (from out/, not on device)

- Zip md5 OK. `ro.build.fingerprint=google/shiba/shiba:17/CP2A.260805.005/15828068:user/release-keys`, userdebug.
- Kernel in boot.img: `Linux version 6.1.157-android14-11-g14047afecd8b-ab16012876` (stock).
- Installed: NexusLauncherRelease (system_ext), PrebuiltGmsCore, Velvet, SetupWizard, GoogleDialer,
  GoogleCamera, NowPlaying, ParanoidSense (PixelOS face unlock), ColumbusService (Quick Tap),
  TouchGestures, Updater, com.google.android.extservices APEX.
- NOT included vs the Mist build: DeviceConnectivityService (Clear Calling), JamesDSP, Mist's Now
  Playing lock-screen port, Auto HBM. Launcher3/Trebuchet is not installed (Pixel Launcher only).

## 5. Build-server notes

- The server has Google-style remote execution configured (`/srv/rbe/rewrapper`, `exec_strategy=remote_local_fallback`);
  that is why a full build took 26 min. Its dependency scanner occasionally dies at startup
  (`scandeps_server terminated during startup` → `FAILED: ... turbine/framework.jar`). That is a
  transient: just relaunch the build.
- Upload to SourceForge confirmed 2026-09-18 04:49 UTC: `pixelos/shiba/PixelOS_shiba-17.0-20260918-0417.zip` (2,695,683,629 bytes),
  `.md5sum`, and `img/{boot,vendor_boot,vendor_kernel_boot,dtbo}.img`.

## 6. Rebuild with the Now Playing PCS fix (2026-09-18, later)

The zuma allowlist fix from mistos/FEATURES.md ("Now Playing stopped recognising anything") was applied to
`device/google/zuma/allowlist_com.google.android.as.xml` in this tree too (same LineageOS file) and both devices
rebuilt. shiba: `PixelOS_shiba-17.0-20260918-0535.zip` replaces 0417 on SourceForge. husky: `PixelOS_husky-17.0-20260918-0608.zip` replaces 0449 (md5 OK, allowlist verified in the built product image).

Gotcha seen on the rebuild: `m pixelos` emits the new zip AND refreshes the previous zip name, because both
`PixelOS_<dev>-<date>.zip` files are hard links to `lineage_<dev>-ota.zip`. After a rebuild the old-named zip has
NEW content and its old `.md5sum` no longer matches. Always take the newest-named zip and its own md5.

## 7. Open items

- Flash on a Pixel 8 and check: boot, face unlock (ParanoidSense, not Google's), fingerprint, camera,
  Quick Tap. Test keys: Play Integrity handled by the user's Tricky Store + PIF setup as before.
- husky: built 2026-09-18 with the same patches → `PixelOS_husky-17.0-20260918-0449.zip` (2,703,178,180 bytes,
  md5 OK, fingerprint google/husky/husky:17/CP2A.260805.005). Uploaded to SourceForge `pixelos/husky/` (+`img/`).
  Untested on hardware (no Pixel 8 Pro available).
- If PixelOS ever adds official shusky trees, drop the local manifest and use theirs.
