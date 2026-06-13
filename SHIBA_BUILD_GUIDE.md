# Building Project Infinity-X (Android 16) for Google Pixel 8 "shiba"

> **Device:** Google Pixel 8 — codename **`shiba`** (shares the **`shusky`** device tree with the 8 Pro `husky`; SoC platform = **`zuma`**).
> **ROM:** Project Infinity-X, branch **`16`** (= LineageOS `lineage-23.2` = Android 16 QPR2).
> **Variant built:** `userdebug`, **vanilla (no GApps)**, maintainer `chiranz`.
> This is the exact, reproducible recipe — real repo names, real branches, real file contents, and every problem hit + the fix. Copy-paste ready.

---

## What was built (reference output)

- `out/target/product/shiba/Project_Infinity-X-3.11-shiba-13.06.2026-VANILLA-UNOFFICIAL.zip` (~1.8 GB)
- First full build: ~31 min on 96 cores (warm soong). Incremental rebuild after a 1-file change: ~10 min.
- Verified working on-device: boot, WiFi, data, calls, camera, fingerprint, **Google Class-3 face unlock**, **JamesDSP**.

---

## 0. Server used (so you can gauge yours)

96 cores · 251 GB RAM · 3.6 TB free · Ubuntu 24.04 · `repo git git-lfs ccache python3 java make` all present.
Minimum realistic: 8+ cores, 32 GB RAM (or big swap), **~300 GB free disk**.

```bash
nproc --all; free -h; df -h .
for t in repo git git-lfs ccache python3 java make; do command -v $t || echo "$t MISSING"; done
```

---

## 1. Source root

Everything lives in **`/home/chiranz/infinityx`**. Adjust if you use a different path (update the wrapper scripts too).

```bash
mkdir -p /home/chiranz/infinityx && cd /home/chiranz/infinityx
```

---

## 2. The cookiefile gate (DO THIS FIRST — sync won't run without it)

Infinity-X ships a **patched `repo`** that refuses *all* git ops until `git config http.cookiefile` is set. Best to use **real** Google cookies (Pixel trees pull ~75% of repos from `android.googlesource.com`; real cookies = no throttling).

1. On a browser logged into your Google account: <https://android.googlesource.com/new-password> → copy the **Linux/bash** snippet.
2. Run it on the server. It does roughly:
   ```bash
   git config --global http.cookiefile ~/.gitcookies
   # ...appends a token line for .googlesource.com to ~/.gitcookies
   ```
3. Verify (without printing the token):
   ```bash
   git config --global http.cookiefile
   git ls-remote https://android.googlesource.com/platform/build refs/heads/main | head -1  # should return a hash
   ```

> Minimal fallback if you can't get real cookies: `touch ~/.gitcookies && git config --global http.cookiefile ~/.gitcookies` — passes the gate, but anonymous AOSP fetches may throttle (the retry loop in §4 handles it).

---

## 3. Init the manifest

```bash
cd /home/chiranz/infinityx
repo init --depth=1 --no-repo-verify --git-lfs \
  -u https://github.com/ProjectInfinity-X/manifest -b 16 \
  -g default,-mips,-darwin,-notdefault
```

> The `ERROR: Missing Cookiefile` text may print during init — **init still succeeds** (`.repo/` populates). The gate bites at *sync* time, which §2 already handled.

---

## 4. Device local manifest (Pixel 8)

Create **`.repo/local_manifests/roomservice_infinity_shiba.xml`** with EXACTLY this. Key Pixel-8 decisions baked in: device/SoC trees on **16.2** (QPR2, matches lineage-23.2), kernel+blobs on **16.0** (only branch; same firmware fingerprint `BP4A.260205.001`), gs-common on **lineage-23.2**, **no `<remote>` re-declarations** (they're already in Infinity's `default.xml`), Pixel 8a (akita) omitted.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <!-- Common Pixel + extras (platform-matched) -->
  <project name="LineageOS/android_device_google_gs-common" path="device/google/gs-common" revision="lineage-23.2" remote="github" clone-depth="1" />
  <project name="crdroidandroid/proprietary_vendor_google_faceunlock" path="vendor/google/faceunlock" revision="16.0" remote="gitlab" clone-depth="1" />
  <project name="ionutsandroidbuilds/proprietary_vendor_google_camera" path="vendor/google/camera" revision="zuma" remote="gitlab" clone-depth="1" />
  <project name="ionutsandroidbuilds/proprietary_vendor_google_pixels_extras" path="vendor/google/pixels_extras" revision="16.0" remote="gitlab" clone-depth="1" />
  <project name="crdroidandroid/android_vendor_bcr" path="vendor/bcr" revision="16.0" remote="github" clone-depth="1" />
  <project name="ionutgherman/vendor_JamesDSP" path="vendor/JamesDSP" revision="aidl" remote="github" clone-depth="1" />

  <!-- Pixel 8 (shiba) + 8 Pro (husky) share the shusky tree; SoC = zuma -->
  <project name="ionutsandroidbuilds/android_device_google_shusky" path="device/google/shusky" revision="16.2" remote="github" clone-depth="1" />
  <project name="ionutsandroidbuilds/android_device_google_zuma" path="device/google/zuma" revision="16.2" remote="github" clone-depth="1" />
  <project name="ionutsandroidbuilds/android_device_google_shusky-kernels" path="device/google/shusky-kernels" revision="16.0" remote="github" clone-depth="1" />

  <!-- Proprietary blobs (only 16.0 branch; fingerprint BP4A.260205.001) -->
  <project name="ionutsandroidbuilds/proprietary_vendor_google_shiba" path="vendor/google/shiba" revision="16.0" remote="gitlab" clone-depth="1" />
  <project name="ionutsandroidbuilds/proprietary_vendor_google_husky" path="vendor/google/husky" revision="16.0" remote="gitlab" clone-depth="1" />
</manifest>
```

Sanity-check it resolves before syncing:
```bash
repo manifest | grep -E "shusky|zuma|shiba|gs-common"
```

---

## 5. Sync

```bash
cd /home/chiranz/infinityx
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16
```

Resilient version (resumable; survives transient drops) — save as `.staging/run_sync.sh`, run detached:
```bash
#!/usr/bin/env bash
cd /home/chiranz/infinityx || exit 99
n=0; while :; do n=$((n+1)); echo "== SYNC ATTEMPT $n =="
  repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16 && { echo "SYNC COMPLETE"; break; }
  [ $n -ge 8 ] && { echo "SYNC GAVE UP"; break; }; echo "retry in 30s"; sleep 30
done
```
```bash
nohup bash .staging/run_sync.sh > sync.log 2>&1 &   # ~1180 repos; authenticated+shallow = clean
```

---

## 6. Add the `infinity_shiba` product (the device tree only has lineage_/aosp_)

`lunch infinity_shiba` has nothing to resolve out of the box. Create **`device/google/shusky/infinity_shiba.mk`** with EXACTLY this final content (it already includes the JamesDSP inherit and the APR allow-list from §8/§9):

```make
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-FileCopyrightText: The Calyx Institute
# SPDX-License-Identifier: Apache-2.0
#

# Inherit some common stuff
$(call inherit-product, vendor/infinity/config/common_full_phone.mk)

# Inherit device configuration
DEVICE_CODENAME := shiba
DEVICE_PATH := device/google/shusky
VENDOR_PATH := vendor/google/shiba
$(call inherit-product, $(DEVICE_PATH)/aosp_$(DEVICE_CODENAME).mk)

# Audio: JamesDSP (AIDL). Device tree does not pull this in, so inherit it
# explicitly here (Google face unlock is already wired via zuma/common.mk).
$(call inherit-product-if-exists, vendor/JamesDSP/config.mk)

# OmniStyle + bootanimation land in bare system/ and trip generic_system.mk's
# GSI artifact-path requirement (TWO checkers: soong + kati; soong ignores the
# 'relaxed' flag, so allow-list is the only thing both honor). Functionally inert.
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/priv-app/OmniStyle/% \
    system/media/bootanimation.zip

# Device identifier. This must come after all inclusions
PRODUCT_BRAND := google
PRODUCT_MODEL := Pixel 8
PRODUCT_NAME := infinity_$(DEVICE_CODENAME)

# Boot animation
TARGET_BOOT_ANIMATION_RES := 1080

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="shiba-user 16 BP4A.260205.001 14624666 release-keys" \
    BuildFingerprint=google/shiba/shiba:16/BP4A.260205.001/14624666:user/release-keys \
    DeviceProduct=$(DEVICE_CODENAME)

$(call inherit-product, $(VENDOR_PATH)/$(DEVICE_CODENAME)-vendor.mk)
```

Then register it in **`device/google/shusky/AndroidProducts.mk`** — add the `infinity_shiba.mk` line + the lunch choice:

```make
PRODUCT_MAKEFILES := \
    $(LOCAL_DIR)/aosp_husky.mk \
    $(LOCAL_DIR)/aosp_shiba.mk \
    $(LOCAL_DIR)/infinity_shiba.mk \
    $(LOCAL_DIR)/lineage_husky.mk \
    $(LOCAL_DIR)/lineage_shiba.mk

COMMON_LUNCH_CHOICES := \
    infinity_shiba-userdebug
```

> ⚠️ These two files live in the `shusky` tree (revision 16.2). A `repo sync --force-sync` can revert them — re-apply after any destructive re-sync. (Keep a copy in `.staging/`.)

---

## 7. ⚠️ Build-shell quirks specific to this environment (cost the most debugging time)

Before `lunch`/`m`, in the **same shell**:

1. **`unset -f grep find`** — the Claude Code shell injects function wrappers for `grep`/`find` (route through `ugrep`). AOSP `lunch` calls bare `grep` → `ugrep: no PATTERN specified` → `lunch` fails with `Cannot locate config makefile for product "infinity_shiba-userdebug"` (it mis-parses, treating the whole string as the product). **This also breaks `lunch lineage_shiba`, proving it's the shell, not the ROM.** The wrappers do NOT leak into `make` subprocesses, so unsetting in the build shell is enough.
2. **Do NOT use `set -u`** in your build wrapper — `build/envsetup.sh` references unset vars (`TOP`) and aborts under nounset, leaving `lunch` undefined.

If your shell is a plain interactive bash without those wrappers, the `unset -f` is a harmless no-op — keep it in for safety.

---

## 8. Features: Google Class-3 face unlock & JamesDSP (Pixel 8 specifics)

### Face unlock — already correct, just verify
The Pixel 8 strong (Class-3, banking-capable) face stack is **already wired** for shiba:
- HAL: `vendor/google/shiba` ships `com.google.android.hardware.biometrics.face.apex` (inherited via `shiba-vendor.mk`).
- `device/google/zuma/common.mk` inherits `vendor/google/faceunlock/config.mk`, which sets `TARGET_FACE_UNLOCK_SUPPORTED := false` (**disables Infinity's basic Class-1 face unlock**) and adds `SettingsGoogleFutureFaceEnroll` + the `biometrics.face` permission.
- Nothing to change. Verify post-build (§11). On-device: Settings → Security → Face Unlock should show Google's enrollment flow.

### JamesDSP — needs the inherit (§6) AND a config fix (§9)
`vendor/JamesDSP/config.mk` is **orphaned** (nothing inherits it) → the `inherit-product-if-exists` line in §6's `infinity_shiba.mk` fixes that. But that alone still yields *"failed to load jamesdsp.so"* on-device — see §9.

---

## 9. ⚠️ THE JamesDSP fix unique to Pixel 8 (audio_effects_config collision)

**Symptom on-device:** JamesDSP says *"failed to load jamesdsp.so — please install module and reboot."*

**Why (shiba-specific):** Two `PRODUCT_COPY_FILES` write the same path `/vendor/etc/audio_effects_config.xml`:
- `device/google/zuma/common.mk:459` (the **zuma** config — **wins**)
- `vendor/JamesDSP/config.mk` (loses → JamesDSP's `<library>`/`<effect>` are dropped)

So `libjamesdspaidl.so` ships but is never registered with the audio framework.

**Fix:** add the two JamesDSP entries into the **winning** file, `device/google/zuma/audio_effects_config.xml` — same way the maintainer already added ViPER4Android (`v4a_aidl`):

In `<libraries>` (after the `v4a_aidl` line):
```xml
        <library name="jdsp" path="libjamesdspaidl.so"/>
```
In `<effects>` (after the `v4a_standard_re` line):
```xml
        <effect name="jamesdsp" library="jdsp" uuid="f27317f4-c984-4de6-9a90-545759495bf2" type="f98765f4-c321-5de6-9a45-123459495ab2"/>
```

> ⚠️ This is in the **zuma** tree (revision 16.2) → re-sync-fragile, same as §6. Keep a copy; re-apply after force-sync. (Or move it into a device RRO you own for permanence.)

---

## 10. ⚠️ Artifact Path Requirement failures (you WILL hit these on shiba)

When you first `lunch`+build, you get (in this order):

1. **soong stage:** `internal error: Device makefile produces files inside .../generic_system.mk's artifact path requirement` → `system/priv-app/OmniStyle/OmniStyle.apk`
2. **kati stage:** `artifact_path_requirements.mk:31: error` → `system/media/bootanimation.zip`

There are **two separate checkers** with different rules (soong ignores `PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := relaxed`; only the **ALLOWED_LIST** satisfies both). The fix is already in §6's `infinity_shiba.mk`:
```make
PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
    system/priv-app/OmniStyle/% \
    system/media/bootanimation.zip
```
APR is a GSI-compatibility lint — allow-listing has **zero** functional effect on a real Pixel 8 image.

**Validate cheaply** (runs both checkers in ~2 min — don't gamble a full build):
```bash
unset -f grep find; source build/envsetup.sh; unset -f grep find
lunch infinity_shiba-userdebug >/dev/null && m nothing 2>&1 | tail -5   # want "build completed successfully"
```

---

## 11. Build

Save as `.staging/run_build.sh` (note: **no `set -u`**, **`unset -f grep find`**, ccache on):
```bash
#!/usr/bin/env bash
cd /home/chiranz/infinityx || exit 99
unset -f grep find 2>/dev/null || true
source build/envsetup.sh
unset -f grep find 2>/dev/null || true
export USE_CCACHE=1 CCACHE_DIR=/home/chiranz/infinityx/.ccache
ccache -M 50G >/dev/null 2>&1 || true
export INFINITY_MAINTAINER=chiranz
export WITH_GAPPS=false
lunch infinity_shiba-userdebug || { echo "LUNCH FAILED"; echo "BUILD DONE rc=90"; exit 90; }
m bacon -j$(nproc --all); rc=$?
echo "=== BUILD DONE rc=$rc ==="
[ $rc -eq 0 ] && find out/target/product/shiba -maxdepth 1 -name "Project_Infinity-X-*.zip"
echo "BUILD_FINAL_RC=$rc"
```
```bash
nohup bash .staging/run_build.sh > build.log 2>&1 &
tail -f build.log   # watch; ignore "Build sandboxing disabled due to nsjail error" (harmless)
```

---

## 12. Verify the output (especially JamesDSP — don't ship blind)

```bash
P=out/target/product/shiba
ls -lh $P/Project_Infinity-X-*.zip; sha256sum $P/Project_Infinity-X-*.zip

# JamesDSP MUST be registered in the loaded config (this is the bug from §9):
grep -i jamesdsp $P/vendor/etc/audio_effects_config.xml          # expect the jdsp library + jamesdsp effect
ls -lh $P/vendor/lib64/soundfx/libjamesdspaidl.so $P/product/app/JamesDSP/JamesDSP.apk

# Google face unlock present, basic one absent:
find $P -iname "*biometrics.face*" -o -ipath "*SettingsGoogleFutureFaceEnroll*"
find $P -ipath "*org.lineageos.faceunlock*"                       # expect NOTHING

# firmware identity (see §13):
grep -E "^ro.build.(id|fingerprint|version.security_patch)=" $P/system/build.prop
grep -E "^ro.vendor.build.(fingerprint|security_patch)=" $P/vendor/build.prop
```

---

## 13. Firmware IDs you'll see on shiba (so you don't get confused)

| Property | Value (this build) | Meaning |
|---|---|---|
| `ro.build.id` ("Build number") | `BP4A.251205.006` | AOSP source tag the ROM was built from (Dec 2025). Lags stock — normal. |
| `ro.build.fingerprint` | `google/shiba/shiba:16/BP4A.260205.001/.../release-keys` | Set to a real Feb-2026 Google build → Play Integrity. Matches the blobs. |
| system `security_patch` | `2026-06-01` | Framework patch (kept current). |
| `ro.vendor.build.security_patch` | `2026-02-05` | Firmware/blob patch (tied to the 16.0 blobs). |

- Build-ID letter = **calendar cycle**, not Android version: `BP4A` = 2025 cycle, `CP1A` = 2026 cycle. Both are Android 16. Google's "May 2026" stock (`CP1A.260505.005`) is a newer cycle; our base is the BP4A blobs (only ones published for shiba).
- **Don't** spoof the fingerprint to a newer string than your blobs — that *breaks* Play Integrity. The current setup is coherent (fingerprint matches the Feb-2026 blobs).
- To genuinely move to the May-2026 (CP1A) base you'd need: CP1A shiba blobs (not published yet) + flash the matching stock bootloader/radio on the phone + re-sync.

---

## 14. Flashing the Pixel 8 (A/B + init_boot)

Build emits these in `out/target/product/shiba/`: `boot.img init_boot.img dtbo.img vendor_boot.img vendor_kernel_boot.img system.img vendor.img product.img system_ext.img` + the OTA zip.

**First install (wipes data):**
```bash
fastboot flashing unlock                 # wipes
fastboot flash init_boot init_boot.img
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash vendor_boot vendor_boot.img
# reboot to the ROM recovery → factory reset → Apply Update → ADB sideload:
adb sideload Project_Infinity-X-3.11-shiba-*.zip
```

**Update / re-flash same version (KEEPS data — used for the JamesDSP fix):**
```bash
# reboot to recovery → Apply Update → ADB sideload (NO factory reset):
adb sideload Project_Infinity-X-3.11-shiba-*.zip
adb reboot
```

- First boot 3–8 min (ART). Looping boot animation ≠ bootloop.
- `test-keys` warning is normal (self-built/unofficial).
- Bootloop → `adb logcat` / `last_kmsg`; usual culprits on shiba: sepolicy denial or blob/firmware mismatch.

---

## 15. Post-flash smoke test (shiba)

WiFi · mobile data · calls · camera (all lenses) · **fingerprint** · **Face Unlock (Google enrollment flow)** · **JamesDSP (toggle on, grant effects permission, confirm audio changes)**.

---

## 16. Repeat-build cheat sheet

```bash
cd /home/chiranz/infinityx
# (re-apply the 3 tree edits if you force-synced: infinity_shiba.mk, AndroidProducts.mk, zuma/audio_effects_config.xml)
bash .staging/run_build.sh        # warm ccache → ~10 min incremental
P=out/target/product/shiba; grep -i jamesdsp $P/vendor/etc/audio_effects_config.xml  # always re-verify the fix stuck
```

---

## 17. The three Pixel-8 fixes in one place (if you only remember this)

1. **`unset -f grep find`** + **no `set -u`** in the build shell — else `lunch` mis-resolves.
2. **`PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST`** for `OmniStyle` + `bootanimation.zip` (two APR checkers; `relaxed` alone won't do).
3. **Inject jdsp/jamesdsp into `device/google/zuma/audio_effects_config.xml`** (the winning audio config) — else JamesDSP "fails to load."

Plus the universal first step: **set up `~/.gitcookies`** or sync won't even start.

---

*Worked example: Infinity-X 16 on Pixel 8 (shiba), June 2026. Files to keep in `.staging/`: `roomservice_infinity_shiba.xml`, `infinity_shiba.mk`, the `AndroidProducts.mk` + `zuma/audio_effects_config.xml` diffs, `run_sync.sh`, `run_build.sh`.*
