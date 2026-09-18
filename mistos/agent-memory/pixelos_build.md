---
name: pixelos_build
description: "PixelOS (seventeen / Android 17) build for Pixel 8 shiba in ~/pixelos — setup, device trees, fixes, scripts, status"
metadata: 
  node_type: memory
  type: project
  originSessionId: b533daf7-cfc3-433c-b8d7-c4f36d463653
  modified: 2026-09-18T05:06:47.301Z
---

Started 2026-09-18 on the user's request ("try to build https://github.com/PixelOS-AOSP/android_manifest",
"do not stop until it is built fully"). Separate tree at ~/pixelos (repo init -b seventeen --depth=1 --git-lfs).

- PixelOS has NO official Pixel 8 trees (official_devices lists only Pixel 7/7 Pro, inactive, Android 13).
  Used LineageOS lineage-24.0 (Android 17, Aug 2026) trees via ~/pixelos/.repo/local_manifests/shusky.xml:
  device/google/shusky, device/google/zuma, device/google/shusky-kernels (LineageOS), vendor/google/shiba + husky (TheMuppets, GitHub).
  These are the same upstreams Mist's ionutsandroidbuilds trees fork from.
- PixelOS = LineageOS-based: vendor/lineage (PixelOS fork) + vendor/custom (PixelOS bits: vendor/pixel/gms GMS, Pixel Launcher,
  ColumbusService, bootanimation, updater). Lunch: `lineage_shiba-cp2a-userdebug`; build target `m pixelos` (zip in out/target/product/shiba/PixelOS_*.zip).
- Patches to device/google/shusky/lineage_{shiba,husky}.mk: inherit vendor/custom/config/common_full_phone.mk (not vendor/lineage's),
  `CUSTOM_BUILD := shiba`, and `PRODUCT_BUILD_IGNORE_APEX_CONTRIBUTION_CONTENTS := true`.
- Failure 1 (fixed): Soong "all_apex_contributions depends on undefined module *.google.contributions.prebuilt". Cause: PixelOS GMS ships
  the prebuilt com.google.android.extservices APEX, which makes build/make/core/product_config.mk assume Google mainline prebuilts
  are present (ignore_apex_contributions stays false). Mist never hit it because it has no com.google.android.* mainline APEX in
  PRODUCT_PACKAGES. Fix = the flag above.
- Failure 2 (fixed): Soong "found in multiple namespaces (vendor/google/shiba and vendor/pixel/gms/common)" for
  AICorePrebuilt-aicore_20260302.01_RC00 and DeviceIntelligenceNetworkPrebuiltAstrea → removed both from
  vendor/google/shiba/Android.bp + shiba-vendor.mk (PixelOS GMS ships them).
- Failure 3 (fixed): "Device makefile produces files inside generic_system.mk's artifact path requirement" (GMS/ParanoidSense in
  system/) → PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += system/apex/% system/app/% ... in lineage_{shiba,husky}.mk.
- Failure 4 (fixed): LineageOS android_device_google_shusky-kernels lineage-24.0 has ONLY module lists (no .ko/Image/boot.img).
  Copied the stock CP2A prebuilt set from ~/mistos/device/google/shusky-kernels (ionuts 17.0, verified booting) into
  ~/pixelos/device/google/shusky-kernels/6.1/ (330 .ko, dtbs, Image*, boot.img, dtbo.img). Module lists were identical.
- RESULT: shiba build SUCCEEDED 2026-09-18 04:43 (26 min): out/target/product/shiba/PixelOS_shiba-17.0-20260918-0417.zip
  (2.7 GB, userdebug, test keys, stock kernel 6.1.157, Pixel Launcher/GMS/Velvet/ParanoidSense/ColumbusService/NowPlaying in;
  no DCS/JamesDSP/Auto HBM). Uploaded to SourceForge chiranz: pixelos/shiba/ (+img/), confirmed 04:49.
  husky SUCCEEDED 2026-09-18 (PixelOS_husky-17.0-20260918-0449.zip) after one RBE transient retry; uploaded to pixelos/husky/.
  Neither flashed/tested on hardware. Full write-up + patches in GitHub chiranz07/customrom: pixelos/PIXELOS.md (commit 347d418).
  Server has RBE (/srv/rbe/rewrapper) → full builds ~26 min; "scandeps_server terminated during startup" = transient, relaunch.
- Scripts: ~/pixelos_sync.sh (+log), ~/pixelos_pipeline.sh (post-sync device sync + patch + launch), ~/pixelos_build_supervisor.sh,
  ~/launch_pixelos.sh; logs ~/pixelos_attempt<N>.log, final status ~/pixelos_build_final_status.txt.

**How to apply:** if a later failure appears, check ~/pixelos_attempt*.log for `^FAILED:`; keep the Lineage trees unmodified except the
three product-mk lines above. See [[mistos_rom_build]] and [[feedback_dont_stop_builds_unasked]].
