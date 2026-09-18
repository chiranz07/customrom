# VoltageOS 6.1 (branch `17`, Android 17) for Pixel 8 (shiba) and Pixel 8 Pro (husky)

Built from https://github.com/VoltageOS/manifest branch `17` (AOSP android-17.0.0_r1, manifest
"Forks for 2026-09 ASB", release config `cp2a`), userdebug, signed with a locally generated key set (§4).

**Current release (2026-09-18, third build — face unlock fix, see §9; build 2 fixes in §6):**

| Device | Zip | Size | sha256 |
|---|---|---|---|
| shiba | `voltage-6.1-shiba-20260918-2104-UNOFFICIAL.zip` | 1.55 GB | `dce4ee65ed8c3976e547e5ee98e66bf584ce7a488fcd05c70a6eb5c218e64129` |
| husky | `voltage-6.1-husky-20260918-2116-UNOFFICIAL.zip` | 1.55 GB | `1ae2f303e38c276e673366c6760657e3cc740744b564fdc43f01c6b1bc5b280c` |

Build 3 adds the face unlock fix (§9) on top of build 2. Older builds are removed from SourceForge;
each folder keeps only the latest.

Build times on the 96-core server with RBE: shiba 28:30 from a clean `installclean`, husky 8:34 incremental.

Download: SourceForge project `chiranz`, `voltage/shiba/` and `voltage/husky/` (zip + md5sum), each with an
`img/` folder carrying **boot, init_boot, vendor_boot, vendor_kernel_boot, dtbo** — `init_boot.img` is new in
this build; the first release omitted it even though it is in `AB_OTA_PARTITIONS`, which matters to anyone
flashing images by hand rather than sideloading the zip.

**Signing keys changed between the first and second build** (the original set died with the build server, see
§4). There is no OTA path across a key change: anyone on `…-0808`/`…-0848` must clean-flash.

**Neither build has been confirmed booting on hardware by the maintainer.** First-build feedback from a Pixel 8
Pro tester: ROM boots, calls/SMS/wifi/location work; GApps would not install (fixed, §6). The reported
recovery failure turned out to be tester error and is not a ROM issue — recovery works.

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
- `BatteryStatsService: Unable to load Power.Stats.HAL` — **not a missing HAL.** The AIDL PowerStats HAL is
  declared by the blobs (`vendor/etc/vintf/manifest/android.hardware.power.stats-service.pixel.xml`,
  `android.hardware.power.stats` v2, `IPowerStats/default`) and the service runs. The `hwservicemanager` line
  in the log is a **HIDL 1.0** lookup, which is deprecated and correctly absent; the BatteryStats message
  looks like a boot-order artifact. Corrected 2026-09-18 — an earlier version of this file wrongly called it
  a VINTF gap.

## 7. Recovery — CLOSED, not a ROM issue

The first tester reported recovery hanging on the Google logo. It was tester error: recovery works.
Confirmed independently on Mist-OS, which ships a structurally identical recovery image (same single
vendor ramdisk fragment, same 214 modules, same contents).

Kept only as a record of what was verified while chasing it, so nobody re-runs it: the vendor_boot
recovery ramdisk is complete (`/system/bin/recovery`, `fastbootd`, `minadbd`, 109 res images, both
init.recovery rc files); every DT_NEEDED of every recovery binary resolves inside the ramdisk;
`fstab.zuma` is byte-identical to the one a working third-party recovery used; vendor_kernel_boot
carries all 214 modules including the panel driver and the four recovery touch modules; and
`hardware/google/pixel/recovery`'s `make_device()` does no work at startup.

## 8. Google Play on a vanilla ROM

VoltageOS ships GrapheneOS's **GmsCompat** (sandboxed Play) but no app store, and GmsCompat expects
one: its manifest declares `<package android:name="app.grapheneos.apps"/>` and
`BinderGms2Gca.kt` calls `app.grapheneos.apps.RpcProvider` to refresh the gmscompat config. So without
that store there is no supported route to Play, and the gmscompat config can never update.

**We deliberately do not bundle it.** GrapheneOS asks other OSes not to redistribute their apps or
lean on their servers, and that is their call to make. Tell users instead:

> Install GrapheneOS's Apps store from https://github.com/GrapheneOS/AppStore/releases (v36, MIT),
> then install Play services and Play Store through it. Alternatively flash a GApps package —
> mutually exclusive with GmsCompat, pick one.

For the record, integrating it would be small if that stance ever changes: `INSTALL_PACKAGES` is the
only signature|privileged permission it requests (everything else is normal or appop), so the privapp
allowlist is a single line, and it drops in as an `android_app_import` with `presigned: true,
privileged: true`.

## 9. Face unlock is the software one, not real Class-3 (fixed 2026-09-18)

`vendor/voltage/config/common.mk` ships Megvii/Sense `FaceUnlock` and sets `ro.face.sense_service=true`.
That is the same hijack Mist-OS root-caused (mistos/FEATURES.md §2): the framework registers the
software provider and never constructs the real Pixel `FaceProvider`, even though the real Class-3 face
HAL apex is present in the TheMuppets blobs and its service starts (confirmed in the tester's logcat).

Fix, in `voltage_{shiba,husky}.mk` rather than upstream's `common.mk`, because the product makefile is
parsed *before* the parent's `?=` and therefore wins:

```make
TARGET_FACE_UNLOCK_SUPPORTED := false
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.biometrics.face.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/android.hardware.biometrics.face.xml
```

The second half matters: the same upstream block also copies the face feature XML, and dropping it
would remove face unlock from Settings altogether. Verify with `dumpsys face` → `provider: FaceProvider`,
`Strength: 15`. If enrolment doesn't appear, add crdroid's `vendor/google/faceunlock` enabler repo,
which is what Mist uses for the enrolment UI and its sepolicy.

## 10. Open question: libperfmgr log noise

Voltage logs 409 `libperfmgr: Failed to find <field> in JSON config` lines at boot; Mist-OS logs zero.
That string does **not** exist in the ROM's `hardware/google/pixel/power-libperfmgr` source — the
source-built version says `"Failed to read Node[i]'s <field>, set to 'true'"` at INFO for a missing
optional key — so the lines are coming from elsewhere, probably a vendor binary, and may be the same
benign optional-key pattern logged at ERROR. **Not confirmed as a bug.** To settle it: one full log
line with tag and PID from a Voltage device, plus whether the running power HAL is the source-built one
or a blob. Do not repeat the earlier PowerStats mistake of assuming a scary log line is a defect.
