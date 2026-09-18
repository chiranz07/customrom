# VoltageOS 6.1 (branch `17`, Android 17) for Pixel 8 (shiba) and Pixel 8 Pro (husky)

Built from https://github.com/VoltageOS/manifest branch `17` (AOSP android-17.0.0_r1, manifest
"Forks for 2026-09 ASB", release config `cp2a`), userdebug, signed with a locally generated key set (§4).

**Current release (2026-09-18, second build — tester-feedback fixes, see §6):**

| Device | Zip | Size | sha256 |
|---|---|---|---|
| shiba | `voltage-6.1-shiba-20260918-1629-UNOFFICIAL.zip` | 1.58 GB | `bf66ab74c7a8f478804583bec810792ad83eb4d34cf6fe0c73f075dd66d81f44` |
| husky | `voltage-6.1-husky-20260918-1659-UNOFFICIAL.zip` | 1.58 GB | `a9db735e3003872c5047aaaf5afeb05115bac4da0e6155b45cab447b0f6335cb` |

Build times on the 96-core server with RBE: shiba 28:30 from a clean `installclean`, husky 8:34 incremental.

Download: SourceForge project `chiranz`, `voltage/shiba/` and `voltage/husky/` (zip + md5sum), each with an
`img/` folder carrying **boot, init_boot, vendor_boot, vendor_kernel_boot, dtbo** — `init_boot.img` is new in
this build; the first release omitted it even though it is in `AB_OTA_PARTITIONS`, which matters to anyone
flashing images by hand rather than sideloading the zip.

**Signing keys changed between the first and second build** (the original set died with the build server, see
§4). There is no OTA path across a key change: anyone on `…-0808`/`…-0848` must clean-flash.

**Neither build has been confirmed booting on hardware by the maintainer.** First-build feedback from a Pixel 8
Pro tester: ROM boots, calls/SMS/wifi/location work; recovery does not (§7); GApps would not install (fixed, §6).

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

## 6. Second build (2026-09-18 16:29 / 16:59) — what changed and why

All of these came out of the first tester's report plus their `logcat` and NikGapps install log.

1. **GApps could not install — every partition was built exact-fit, 0 bytes free.** The installer log showed
   system 917.1M/914.3M used, product 879.8M/877.2M, system_ext 584.5M/582.8M, and NikGapps-core needs 282 MB.
   Root cause is one line: `device/google/zuma/BoardConfig-common.mk` ends with
   `-include vendor/lineage/config/BoardConfigReservedSize.mk` (LineageOS's "reserve space for gapps install"
   hook). VoltageOS has no `vendor/lineage`, so that include silently did nothing — while Voltage *already
   ships* an identical `vendor/voltage/config/BoardConfigReservedSize.mk` that nothing referenced. Fix: add
   `-include vendor/voltage/config/BoardConfigReservedSize.mk` next to it. Verified in the built images:
   **product 1134 MB free, system 92 MB, system_ext 91 MB.**
2. **Fingerprint was completely dead** even though the Goodix HAL was running and talking to its Trusty TA.
   `AuthService: Fingerprint configuration exists, but FingerprintService is null` + four
   `SystemServiceRegistry: No service published for: fingerprint` in system_server. The device tree never
   declares the `android.hardware.fingerprint` feature, so SystemServer never starts FingerprintService and
   Settings hides fingerprint entirely (same bug and fix as Mist-OS, `mistos/FEATURES.md` §3). Fix:
   `PRODUCT_PACKAGES += android.hardware.fingerprint.prebuilt.xml` in `voltage_{shiba,husky}.mk`; it installs
   (`soc_specific`) to `/vendor/etc/permissions/android.hardware.fingerprint.prebuilt.xml` — verified present.
3. **Virtual biometric HALs removed.** `com.android.hardware.biometrics.{face,fingerprint}.virtual` shipped in
   `/system_ext/apex` and registered extra HAL instances (`FingerprintService: Before:getDeclaredInstances …
   a.length=1 / After: a.length=2`), hijacking the real Goodix/Google HALs. Dropped for `voltage_*` products
   only, via `ifeq ($(filter voltage_%,$(TARGET_PRODUCT)),)` guards in `build/make/target/product/base_product.mk`
   and `hardware/google/pixel/common/pixel-common-device.mk`. Verified absent from the built `system_ext`.
4. **Three SELinux denials fixed** (41 denials at boot, these were the top ones):
   `dontaudit gxp_logging traced_producer_socket:sock_file write` (15/boot),
   `allow hal_camera_default vendor_camera_data_file:dir create` (10/boot, `video_bokeh_node`),
   and a new `device/google/shusky/sepolicy/vendor/hal_face_default_extra.te` with
   `allow hal_face_default metadata_file:dir r_dir_perms`. All three verified in the shipped `vendor_sepolicy.cil`.
5. **`boot.img` re-stamped** with `--os_version 17 --os_patch_level 2026-09` (the tree's `PLATFORM_SECURITY_PATCH`),
   which the prebuilt-boot-image path skips. Kernel banner verified unchanged: stock
   `6.1.157-android14-11-g14047afecd8b-ab16012876`.

**A fourth sepolicy rule was attempted and dropped:** `allow hal_graphics_composer_default
pixeldisplayservice_app:binder call` (hwc calling into PixelDisplayService, denied at boot). It does not
compile — `unknown type hal_graphics_composer_default` — because a system_ext *private* policy cannot see a
vendor type, and the mirror-image rule on the vendor side cannot see the system_ext-private app type. Fixing it
properly needs the type exported. Catch this class of error cheaply with `m selinux_policy` before a full build.

**Deliberately NOT trimmed:** `DevicePersonalizationAiAiPrebuiltPixel2023` (ASI, 110 MB), `AICorePrebuilt`,
`DeviceIntelligenceNetworkPrebuiltAstrea` (36 MB), `HotwordEnrollment*`, `NowPlayingPrebuilt`,
`PixelCameraServices` (144 MB). Without GMS they idle in failure loops (ASI logged 1748 warnings in three
minutes), but the working assumption for this ROM is that **users flash GApps afterwards**, which makes them
real features again. The space they take is no longer a problem now that the reserve exists.

**Known limitations confirmed from the tester's log:**
- **eSIM** needs GMS. The whole Pixel eSIM stack is present (`EuiccGoogle` 16 MB, `EuiccSupportPixel-P23` with
  its `esim-full-v1.img`/`DKA_*.up` firmware, permissions, overlays, `android.hardware.telephony.euicc{,.mep}.xml`,
  no privapp denials), but `EuiccGoogle` failed with
  `ApiException: 17: API: UsageReporting.API is not available on this device`. Expected to work once GApps is
  installed; nobody has activated an eSIM on this ROM yet.
- **GmsCompat and flashed GApps are mutually exclusive.** Pick one.
- RCS: `com.shannon.rcsservice` UCE services are not found at boot.
- No network fault found: wifi validates, DNS resolves; `resolv: Validation failed` ×6 is opportunistic
  DNS-over-TLS probing carrier servers that do not answer on 853, and `res_nsend … terrno: 101` is ENETUNREACH
  on AAAA lookups with no IPv6 route. `Netd: Unable to start HIDL NetdHwService` is the deprecated HIDL path;
  AIDL netd registers immediately after.
- `BatteryStatsService: Unable to load Power.Stats.HAL` — `android.hardware.power.stats@1.0::IPowerStats/default`
  is in neither framework nor device VINTF, so rail-level battery attribution is missing. Not yet fixed.

## 7. Recovery does not boot (open, first build; unchanged in the second)

Symptom on the tester's Pixel 8 Pro: after flashing, rebooting to recovery hangs on the Google logo. Flashing
the `img/` files did not help; an older crDroid recovery (20250515) boots fine.

What has been checked, from the published images themselves:
- The `vendor_boot` recovery ramdisk is complete — `/system/bin/recovery`, `fastbootd`, `minadbd`, 109
  `res/images`, `init.recovery.husky.rc` + `init.recovery.zuma.rc`.
- `vendor_kernel_boot` carries all 214 modules including the display stack (`exynos-drm`, `gs-panel`,
  `panel-google-hk3` = husky's panel) and the four recovery touch modules from
  `device/google/shusky/recovery/modules.load.vendor_kernel_boot`.
- Structure is a single unnamed type-0x1 vendor ramdisk fragment, which is what
  `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true` produces when
  `BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT` is not set — and it is **byte-for-byte the same shape as the
  Mist-OS images**, whose module set is identical. So this is not Voltage-specific packaging; it very likely
  affects Mist-OS too, where recovery has never been tested either.
- `hardware/google/pixel/recovery/recovery_ui.cpp`'s `make_device()` does no work at startup, so the Pixel
  recovery UI library is not the hang.

Still needed to root-cause, in order of value: (1) does recovery work on Mist-OS on a Pixel 8 — splits the
hypothesis in half; (2) while stuck at the logo, does `adb devices` enumerate — separates "init/recovery alive,
display dead" from "nothing running"; (3) is the device on stock CP2A firmware — a ROM zip never updates
bootloader/radio, and the tester came from an Android 16 build.
