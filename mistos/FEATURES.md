# Feature recipes — how each thing was made to work on Mist-OS 17 / Pixel 8 (shiba)

One section per feature: symptom → root cause → exact files → how to re-apply → how to
verify. Everything here is in `patches/rom/` (as diffs) and `files/` (as plain copies);
`HANDOFF.md` has the longer investigation history. All items were verified on a real
Pixel 8 on 2026-09-17 unless marked otherwise.

---

## 1. GApps set — the "right size" (`vendor/gms/gms_mini.mk`)

Mist ships three GMS levels (`gms_pico`, `gms_mini`, `gms_full`). `mist_shiba.mk` hardcodes
`TARGET_USES_MINI_GAPPS := true`, and **this trimmed `gms_mini.mk` is the set we settled on**
after finding that several "bloat" removals broke real things. Exact file: `files/vendor/gms/gms_mini.mk`.

**Shipped (keep all of these):**
- system/app: `GoogleExtShared`, `GooglePrintRecommendationService`
- system/priv-app: `DocumentsUIGoogle`, `TagGoogle`
- system_ext/priv-app: `DeviceConnectivityServicePrebuilt_26.01.00` (Clear Calling), `GoogleServicesFramework`, `NexusLauncherRelease`, `SetupWizardPixelPrebuilt_versioned`, `WallpaperPickerGoogleRelease`
- product/app: `CalculatorGooglePrebuilt`, `CalendarGooglePrebuilt`, `Chrome`(+Stub), `GoogleContacts`, `GoogleTTS`, `LatinIMEGooglePrebuilt` (Gboard), `LocationHistoryPrebuilt`, `MarkupGoogle_v2`, `PixelThemesStub2025`, `PixelWallpapers2025`, `SoundPickerPrebuilt`, `talkback`, `TrichromeLibrary`(+Stub), `WebViewGoogle`(+Stub), `arcore`
- product/priv-app: `AndroidAutoStubPrebuilt`, `CarrierLocation`, `ConfigUpdater`, `GoogleDialer`, `GoogleRestorePrebuilt-v1007163`, `Phonesky` (Play Store), `PrebuiltDeskClockGoogle`, `PrebuiltPixelCoreServices`, `SettingsIntelligenceGooglePrebuilt`, `SetupWizardPrebuilt_versioned`, `Velvet` (Google app), `VerifierPrebuiltClassic`
- PrebuiltGmsCore + Dynamite modules, `AndroidPlatformServices`, `com.google.android.gmssystem.prodvic` APEX
- `quick_tap` sysconfig (gated by `TARGET_SUPPORTS_QUICK_TAP := true` in `mist_shiba.mk`)
- Plus everything from the shared blob lists (`product_blobs.mk`, `system_blobs.mk`, `system-ext_blobs.mk`): permission XMLs, sysconfig, Pixel overlays, `EuiccGoogle`, etc.

**Deliberately removed (fine):** Bugle/Messages (AOSP `messaging` used), Wellbeing, `GoogleFeedback`, live wallpapers, kids/supervision, Photos/YouTube/Maps/Drive, telemetry daemons, `FilesPrebuilt` (Files by Google — user preference).

**Three removals that were wrong and had to be restored — don't trim these again:**
1. `Velvet` — `NexusLauncherRelease` NPEs in its own Home Settings when no search-overlay app exists (found by decompiling the launcher). No Velvet = Home Settings crashes every time.
2. `GoogleRestorePrebuilt` — SetupWizard queries its `settingscard` provider on first boot → `SecurityException`/`Unknown authority` without it.
3. `WallpaperPickerGoogleRelease` — the launcher's `wallpaper_picker_package` string expects exactly `com.google.android.apps.wallpaper`; the AOSP picker + overlay "fix" was wrong and got reverted.

Real Google Camera does **not** come from GMS — it's the separate `vendor/google/camera` repo (`ionutsandroidbuilds/proprietary_vendor_google_camera`, branch `zuma`), auto-wired by `device/google/zuma/common.mk`.

---

## 2. Face Unlock (real Google, Class 3)

- **Symptom:** generic AOSP face enrollment UI, `BIOMETRIC_WEAK`.
- **Root cause:** `vendor/lineage/config/mist.mk` unconditionally ships `FaceUnlock` (= `co.aospa.sense`, Megvii software face unlock) and sets `ro.face.sense_service=true`; Mist's patched `FaceService` then registers `SenseProvider` and never constructs the real Pixel HAL's `FaceProvider`. A static RRO `FaceUnlockOverlay` also hijacks Settings' `config_face_enroll`.
- **Fix:** wrap that block in `ifeq ($(filter mist_shiba mist_husky,$(TARGET_PRODUCT)),)` in `mist.mk` (a late `filter-out` in `mist_shiba.mk` does NOT work — parents are parsed after the child). Also: `vendor/google/faceunlock/config.mk` sepolicy dir enabled, duplicate `service.te` deleted, missing `hal_exo_camera_injection_hwservice` type added, `device/google/shusky/sepolicy/vendor/trusty_apploader_faceauth.te` (TA loading from the vendor APEX) and `hal_face_default_extra.te`.
- **Verify:** `dumpsys face` → `provider: FaceProvider`, `Strength: 15`.

## 3. Fingerprint

- **Symptom:** fingerprint absent from Settings.
- **Root cause:** `android.hardware.fingerprint.prebuilt.xml` feature XML never added by this device tree; plus AOSP/pixel-common ship *virtual* biometric HALs that hijack the real ones.
- **Fix:** `PRODUCT_PACKAGES += android.hardware.fingerprint.prebuilt.xml` in `device-shiba.mk`/`device-husky.mk`; delete the `...biometrics.fingerprint.virtual` / `...face.virtual` lines at their source (`build/make/target/product/base_product.mk`, `hardware/google/pixel/common/pixel-common-device.mk`).

## 4. JamesDSP

- Must be `ionutgherman/vendor_JamesDSP` branch `aidl` (Pixel 8's audio HAL only uses the AIDL effects HAL; the Fleur fork is dead code here).
- Its `audio_effects_config.xml` is a generic AOSP template: repoint `pre_processing` to `libaudiopreprocessing.so`, drop `eraser`/`extension_effect` and every `*sw.so` fallback (they don't exist on shiba).
- Screen-off crash (`ForegroundServiceStartNotAllowedException`): new sysconfig `allowlist_james_dsp.xml` with `<allow-in-power-save package="james.dsp"/>`, wired in `vendor/JamesDSP/Android.bp` + `config.mk`.
- `device/google/shusky/sepolicy/vendor/audioserver_jamesdsp.te` for its unlabeled config files / execmem.

## 5. Files app icon (DocumentsUI) without Files by Google

- **Root cause:** Google's real `DocumentsUIGoogle.apk` has a `PreBootReceiver` that disables its own launcher activities at boot (runtime code, not the sysconfig XML — editing/removing the XML override did nothing).
- **Fix:** in `vendor/gms/product/blobs/etc/sysconfig/pixel_experience_2017.xml` disable `com.android.documentsui.PreBootReceiver` and explicitly enable `LauncherActivity`/`ViewDownloadsActivity`.

## 6. StrongBox retry loop (battery)

- **Symptom:** 337× per boot `Could not find ... IRemotelyProvisionedComponent/strongbox for ctl.interface_start`, 1-second binder waits.
- **Root cause:** `device/google/zuma/vintf/manifest.xml` declared an interface the citadel keymint blob never registers (its own VINTF fragment only declares `IKeyMintDevice/strongbox`).
- **Fix:** remove that `<hal>` block. 84 % fewer init error lines.

## 7. Quick Tap (double-tap back)

- **Root cause:** `vendor/gms/gms_mini.mk` sets `TARGET_SUPPORTS_QUICK_TAP ?= false` (full/pico default true), which also makes `vendor/lineage/config/mist.mk` skip `ColumbusService`.
- **Fix:** `TARGET_SUPPORTS_QUICK_TAP := true` in `mist_shiba.mk`/`mist_husky.mk` (plain variables in the child product file are visible to parents). `ColumbusService` (ProtonAOSP's open Quick Tap client) then talks to the Pixel's real `columbus` CHRE nanoapp (ID `0x476f6f676c001019`, in the vendor blobs). For its "screenshot" action, SystemUI's `TakeScreenshotService` permission was changed from `com.android.systemui.permission.SELF` to `android.permission.INTERACT_ACROSS_USERS_FULL` (`frameworks/base/packages/SystemUI/AndroidManifest.xml`, ProtonAOSP 013c5904).
- **Not Pixel Framework** — SystemUIGoogle is not required.

## 8. Clear Calling

- **Root cause:** the DCS app (`com.google.android.apps.pixel.dcservice`, `DeviceConnectivityServicePrebuilt_26.01.00`) was in `vendor/gms/system_ext/packages/privileged_apps/` all along but only listed by `gms_full.mk`. Everything else (its privapp/default-permission XMLs, hidden-API allowlist, `persist.vendor.audio.cca.*` props, the AoC audio HAL's CCA API) was already present and identical to the `cp2a.260605.012` factory image.
- **Fix:** add the module to `gms_mini.mk`. DCS injects its own "Clear calling" toggle into Settings → Sound & vibration (`IA_SETTINGS` / `CLEAR_CALLING`), so no Google Settings app is needed.
- **Verify:** after a call, `logcat -d | grep -E 'CcaAtom|SaveSuezDataEndCall'` → `is_active: 1, is_ui_on: 1, duration_cca_enabled_second: N`. (`getprop persist.vendor.audio.cca.enabled` is not shell-readable — always empty.)

## 9. Now Playing on the lock screen

- **Symptom:** songs recognized (notification appears) but nothing on the lock screen.
- **Root cause:** Mist's "Now Playing" lockscreen feature (`SystemUI/nowplaying/`) is a *local media-session* widget, unrelated to ambient recognition. Android System Intelligence's `AMBIENT_INDICATION_SHOW` broadcast reached SystemUI (permission granted, delivered) but the only receiver (`ax/AxPlatformObservers.kt`) forwards it to a bus nothing consumes. AOSP's hook points exist but are stubs (`res/layout/ambient_indication.xml` = empty `<merge/>`).
- **Fix (port of Pixel's `ambientmusic` from `vendor_pixel-framework` branch `fifteen`, into `frameworks/base/packages/SystemUI`):**
  - `src/com/google/android/systemui/ambientmusic/AmbientIndicationContainer.kt` (API-adapted: `NotificationMediaManager` moved to `media/`, `DelayedWakeLock` ctor, no `setAmbientIndicationTop`) and `AmbientIndicationService.java` (receiver for SHOW/HIDE, TTL alarm, user switch, `stop()`).
  - `src/com/android/systemui/ambientmusic/AmbientIndicationAreaSection.kt` — a `KeyguardSection` bound to AOSP's optional `KEYGUARD_AMBIENT_INDICATION_AREA_SECTION` slot (`@Binds @Named` in `keyguard/ui/view/layout/sections/KeyguardSectionsModule.kt`), which inflates the container into the live `KeyguardRootView`, constrains it above `keyguard_indication_area`, initialises it, starts/stops the service, and reports visibility via `KeyguardInteractor.setAmbientIndicationVisible()`.
  - `res/layout/ambient_indication.xml` (real container, 24 dp symmetric margins), `ambient_indication_inner.xml` (FrameLayout root, centered row), `res/values/dimens_ambient_indication.xml`, 7 icons, 69 `res/anim/audioanim_animation*` frames. Removed the include from the legacy `keyguard_bottom_area.xml`.
  - **Trap:** the legacy `KeyguardBottomAreaView` is still inflated on Android 17 but permanently GONE — anything placed there measures 0×0 (that's why attempt #1 rendered nothing). `R.id.keyguard_indication_area` exists in both the dead and live trees.
- **Verify:** `logcat | grep AmbientIndicationSection` → "Ambient indication bound to keyguard root view"; container's parent in the view dump is `KeyguardRootView` with real bounds; song text visible.

## 10. High brightness mode (manual + QS tile + custom sunlight threshold)

- **How HBM really works on shiba/husky:** the framework's `HighBrightnessModeController` reads `/vendor/etc/displayconfig/display_id_*.xml` (`transitionPoint` 0.71 on the user's panel, `minimumLux 10000`, `timeMaxSecs 300` per `timeWindowSecs 1800`) and only allows brightness above the transition point with adaptive brightness on, lux ≥ 10000, time budget left. The display HAL then engages panel HBM itself.
- **What does NOT work:** writing the panel's sysfs `/sys/class/backlight/panel0-backlight/hbm_mode` from userspace. The write succeeds (with a `sysfs_hbm` sepolicy label) but the composer keeps `Hbm=0` — it re-asserts its own state via the DRM property. Build `...-1723` shipped that and it did nothing.
- **Fix:** patch `services/core/java/com/android/server/display/HighBrightnessModeController.java` to honour four `Settings.Secure` keys via its `SettingsObserver`: `hbm_force` (manual: allowed regardless of lux/time; HDR and Battery Saver still block), `auto_hbm` + `auto_hbm_threshold` (custom lux instead of `minimumLux`), `auto_hbm_no_time_limit` (skip the 5-min cap). Dump shows `mist: mHbmForced=...`.
- **App:** `device/google/zuma/parts` (GoogleParts, `org.lineageos.settings`, system uid): `autohbm/HbmController` writes the keys; manual on = save brightness mode + level, switch to manual mode, `DisplayManager.setBrightness(DEFAULT_DISPLAY, 1.0f)` after 400 ms; off = restore. `AutoHbmFragment`/`AutoHbmActivity` page under Settings → Display → "High brightness mode"; `HbmTileService` QS tile "HBM". Manifest needs `WRITE_SECURE_SETTINGS` + `CONTROL_DISPLAY_BRIGHTNESS`; `Android.bp` gained `androidx.preference`, `SettingsLib`, `SettingsLibSettingsTheme`, `SettingsLibCollapsingToolbarBaseActivity`; theme `Theme.SubSettingsBase` comes from SettingsLib (don't define locally).
- **Verify:** `settings get secure hbm_force`; `dumpsys display | grep -A12 HighBrightnessModeController` (mCurrentMax above 0.71, mHbmMode not off); `hwc-display` logcat lines show `Hbm=1`.
- Automatic mode still needs adaptive brightness ON (the lux feed comes from it).

## 11. Settings crashes (Android 17 Mist Settings)

- Display → Lock screen → *Tap to check phone* crashed: `res/xml/tap_screen_gesture_settings.xml` used `org.evolution.settings.preferences.SecureSettingSwitchPreference` (doesn't exist); replaced with `org.mist.settings.preferences.SecureSettingSwitchPreference`.
- Display → Lock screen → *Shortcuts* crashed (`SET_WALLPAPER` at `com.android.wallpaper`): two static RROs set `config_wallpaper_picker_package` at equal priority; `vendor/pixel-style/rro_overlays/GoogleSettingsOverlay/AndroidManifest.xml` priority raised 1 → 2 so `com.google.android.apps.wallpaper` wins on GMS builds.

## 12. Other fixes worth keeping

- About-phone hardware card: `device/google/shusky/{shiba,husky}/mist_about.prop` + `TARGET_PRODUCT_PROP` (values with spaces must be in a `.prop` file; `PRODUCT_*_PROPERTIES` truncate them — Mist's own `ro.mistos.flavor` shows "Cinnamon" instead of "Cinnamon Bun" for that reason). `MISTOS_MAINTAINER := chiranz`.
- `boot.img` OS-version/patch-level stamp for the prebuilt kernel (`mkbootimg --os_version 17 --os_patch_level <PLATFORM_SECURITY_PATCH>`); required because `BOARD_PREBUILT_BOOTIMAGE` skips the normal stamping.
- Sepolicy: `hal_camera_default` `vendor_camera_data_file:dir create`; `gxp_logging` dontaudit traced socket; `toolbox adb_data_file:dir search` (Mist's `/data/adb` cleanup script was silently failing); `gpuflag` domain (binary then exits 1 by design on zuma — expected).
- Build-only patches: `SQLiteTokenizer.OPTION_CHECK_BRACKETS` port, `libdmabufheap` destructor export, 14 GMS/TheMuppets `PRODUCT_COPY_FILES` collisions removed, super-partition margin 500 MB → 64 MB, RRO name collisions renamed with a `Shusky` prefix.
- Tap/lift to check phone + "Haptic feedback" toggles were already present (zuma overlay `config_dozeTapSensorType=com.google.sensor.single_touch`, `config_dozePulsePickup=true`; Mist adds `doze_tap_gesture_vibrate`).

## 13. Things investigated and NOT done (don't redo)

- **KernelSU+SUSFS kernel:** builds but bootloops (the public `android-gs-shusky-6.1-android16` `private/` trees are a year older than the vendor blobs). Ship the stock prebuilt; root via engstk's prebuilt blu_spark (`gs-susfs`, AnyKernel zip swaps only `Image.lz4`).
- **Pixel Framework (SystemUIGoogle/SettingsGoogle):** RisingOS `sixteen` SystemUIGoogle is smartspace-only (27 k lines stripped; Mist already has that smartspace natively); SettingsGoogle compiles but needs ~8 hand-ported hooks + a jar compat shim and overrides 116 Mist-themed resources. Neither delivers Now Playing or Clear Calling. Leaving the clone inside `vendor/` breaks whole-tree Soong analysis (`Settings_manifest` filegroup missing).
- Boot patch level / attestation, `pixelstats` config, `speaker_version` node: blob/firmware-level, not fixable here.
- eSIM: works; a single ringtone entry with one active SIM is normal.

## Quick Switch (Mist launcher ↔ Pixel Launcher picker) — NOT in 17.0, parked

Users of the Android 16 builds remember Settings > Mistify > Themes > Extras >
**Quick Switch** ("Switch default launcher": Mistify Launcher / Pixel Launcher,
then a SystemUI restart). It is a risingOS feature the Mist team carried on
16/16.2 and dropped entirely on 17.0. Verified 2026-09-18 by fetching the
upstream 16.2 branches and diffing against 17.0.

How it worked on 16.2 (all pieces needed for a port):

- `packages/apps/Mistify` (branch `16.2`): `res/xml/quick_switch.xml`
  (`SystemPropertyListPreference` on `persist.sys.default_launcher`, values 0 =
  Launcher3/Mist, 1 = Pixel), entry in `res/xml/mist_settings_themes.xml`
  ("extras_category"), fragment
  `src/org/mist/settings/fragments/miscellaneous/QuickSwitch.java` (adds the
  Pixel entry only when `persist.sys.quickswitch_pixel_shipped=1`, shows the
  system-restart dialog), `Themes.java` hides the entry unless the
  `with_google_apps` prop is set, strings `quickswitch_*` in
  `res/values/mist_strings.xml`, arrays `quickswitch_launcher_entries/values`
  in `res/values/mist_arrays.xml`.
- `frameworks/base` (branch `16.2`, remote Project-Mist-OS/frameworks_base_qpr2):
  `services/core/java/org/rising/server/QuickSwitchService.java` (disables the
  non-selected launcher per user and hides it from package queries),
  `RisingServicesStarter.java` + call in `SystemServer.java`; hooks in
  `services/core/java/com/android/server/pm/ComputerEngine.java`
  (`shouldHide` in getApplicationInfo/getPackageInfo, filtered
  recreatePackageList/recreateApplicationList),
  `services/core/java/com/android/server/wm/RecentTasks.java`
  (`loadRecentsComponent` reads `config_launcherComponents[idx]`),
  `packages/SystemUI/.../LauncherProxyService.java` (recents component from the
  same array) and `.../navigationbar/gestural/EdgeBackGestureHandler.java`
  (back-gesture-blocking activities from the selected launcher);
  `core/res/res/values/quickswitch_arrays.xml` + `quickswitch_symbols.xml`
  (`config_launcherComponents`, `config_launcherPackages`; index 0 = launcher3,
  1 = nexuslauncher).
- `vendor/lineage` (vendor_mist, branch `16.2`): `config/mist.mk` "Quick Switch"
  block (`TARGET_DEFAULT_PIXEL_LAUNCHER ?= true`; sets
  `persist.sys.default_launcher` and `persist.sys.quickswitch_pixel_shipped`
  under `WITH_GMS`); `config/common_mobile.mk` ships `Launcher3QuickStep`.
- vendor/gms on 16.2 did NOT override Launcher3QuickStep, so both launchers
  were installed.

State on 17.0 (our tree, build 1804/1816):

- Only the two arrays survive in `frameworks/base/core/res/res/values/mist_arrays.xml`
  / `mist_symbols.xml` — and note their order is REVERSED vs 16.2 (index 0 =
  nexuslauncher). Nothing reads them. No service, no hooks, no Mistify page, no
  props. `org/rising/server/` only has ShakeGestureService.
- `vendor/gms/system_ext/packages/privileged_apps/NexusLauncherRelease/Android.mk`
  has `LOCAL_OVERRIDES_PACKAGES := Launcher3 Launcher3QuickStep Trebuchet
  QuickSearchBox`, so the Mist launcher (Launcher3QuickStep, branded
  "Trebuchet" via `lineage_strings.xml`) is not installed at all. Recents are
  pinned to Pixel Launcher by `PixelConfigOverlayCommon`
  (`config_recentsComponentName`).

Port recipe (untested, needs a full build):

1. Remove `Launcher3`/`Launcher3QuickStep`/`Trebuchet` from the override line
   above so both launchers install.
2. Cherry-pick the 16.2 frameworks/base pieces listed above onto 17.0
   (QuickSwitchService, starter, SystemServer call, ComputerEngine, RecentTasks,
   LauncherProxyService — check the 17.0 class name, EdgeBackGestureHandler).
   Fix the array order in `mist_arrays.xml` to match the property values, or
   swap the values.
3. Restore the vendor_mist property block in `vendor/lineage/config/mist.mk`
   (or put the props in `mist_shiba.mk`) and set `with_google_apps=true` (or
   drop that check in Themes.java).
4. Restore the Mistify fragment, XML, strings, arrays; register the fragment in
   Mistify's AndroidManifest if 17.0 requires it.
5. Rebuild, then verify: picker visible, switching + SystemUI restart changes
   both home and recents, other launcher disappears from app lists.

Cheaper alternative if only the picker matters: do step 1 only; Android's own
Settings > Apps > Default apps > Home app then offers both launchers (recents
stay with Pixel Launcher).

## Now Playing stopped recognising anything (found 2026-09-18, after build 1804) — root cause + fix

Symptom (device agent rom-4c, root via KernelSU, logcat): toggle on, DSP fires, nothing ever shown, history
empty. Every launch of com.google.android.apps.pixel.nowplaying logs
`ActivityManager: Service lookup failed: association not allowed between packages
com.google.android.apps.pixel.nowplaying (uid=10392) and com.google.android.as.oss (uid=10365)`.
No music database exists on the device (only ASI's fingerprint code libsense_nnfp_v3.so); the app
pulled 0 bytes while ASI pulled 422 MB of SODA models through PCS at the same moment. Permissions, AppOps,
IFW, network, SoundTrigger all ruled out. Same denial hits com.google.android.inputmethod.latin and
com.google.android.tts against as.oss.

Root cause: `device/google/zuma/allowlist_com.google.android.as.xml` (LineageOS file Mist inherits)
restricts Private Compute Services with `allow-association target="com.google.android.as.oss"` to
`com.google.android.as` and `com.google.android.aicore` only. Google split Now Playing out of ASI into
the standalone app (Play update versionCode 52709, 2026-08-27; the shipped NowPlayingPrebuilt is 315),
so the split app can no longer bind PCS. Stock CP2A.260605.012 (checked in the factory product.img
with debugfs) has NO allow-association with target as.oss at all — PCS is unrestricted on stock.

Fix (in patches/rom/device_google_zuma.patch, files/allowlist_com.google.android.as.xml): remove the
two as.oss-target lines, with a comment. Alternative (narrower): add
`<allow-association target="com.google.android.as.oss" allowed="com.google.android.apps.pixel.nowplaying" />`
plus the same for inputmethod.latin and tts. SystemConfig merges allow-association per target across all
sysconfig XMLs, so a new file in the device tree also works.

Lock-screen pill note: SystemUI's receiver requires the sender to hold
com.google.android.ambientindication.permission.AMBIENT_INDICATION (signature|privileged). NowPlayingPrebuilt
is a non-privileged /product/app on stock too, so the SHOW broadcast must still come from ASI (priv-app);
that is how it worked on build 1804. Verify after flashing:
`adb logcat -d | grep "association not allowed"` (expect nothing);
`du -sh /data/data/com.google.android.apps.pixel.nowplaying` should grow past 284K after some minutes on Wi-Fi.
POST_NOTIFICATIONS for the Now Playing app is in default-permissions_nowplaying.xml (fixed=false) but was
seen DENIED on the device — grant it in Settings if the notification does not show.

The same LineageOS file is in the PixelOS build (pixelos/PIXELOS.md); patched there too.
