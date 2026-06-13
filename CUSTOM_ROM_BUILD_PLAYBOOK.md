# Custom ROM Build Playbook & Handover Notes

> **Purpose:** A field guide for building a LineageOS-derived custom ROM (here: **Project Infinity-X, Android 16, for the Google Pixel 8 "shiba"**) on a Linux build server. Written as an instruction file for the *next agent/engineer* who picks up a fresh build. It captures not just the commands but the **diagnostic methodology, the reasoning behind each decision, and every gotcha hit (with root cause + fix + the general lesson).**
>
> Read the **"Meta-principles"** section first — it's the part that transfers to *any* ROM/device. The rest is the worked example.

---

## 0. TL;DR — the happy path that actually worked

```bash
# 0. Verify environment (cores, RAM, ≥300GB disk, tools). See §2.
# 1. Init the ROM manifest (shallow)
cd /home/chiranz/infinityx
repo init --depth=1 --no-repo-verify --git-lfs \
  -u https://github.com/ProjectInfinity-X/manifest -b 16 \
  -g default,-mips,-darwin,-notdefault

# 2. Drop the (corrected) device local manifest
cp .staging/roomservice_<device>.xml .repo/local_manifests/

# 3. Satisfy the cookiefile gate (see §5.1) — set up gitcookies for android.googlesource.com
git config --global http.cookiefile ~/.gitcookies   # real cookies strongly preferred

# 4. Sync (resilient wrapper, retries, shallow)
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16

# 5. Add the ROM product makefile the device tree lacks (see §6)
#    device/google/shusky/infinity_shiba.mk  +  register in AndroidProducts.mk

# 6. Build — CRITICAL: strip harness shell wrappers, do NOT use `set -u` (see §5.2/§5.3)
unset -f grep find
source build/envsetup.sh
unset -f grep find
export INFINITY_MAINTAINER=chiranz WITH_GAPPS=false
lunch infinity_shiba-userdebug
m bacon -j$(nproc --all)

# 7. Verify the output zip + that requested features are ACTUALLY in the image (see §8)
```

Total wall-clock on a 96-core box: sync ~minutes (authenticated, shallow), first full build ~30 min with warm soong, incremental rebuilds ~10 min.

---

## 1. Meta-principles (the part that generalizes)

These are the lessons that matter more than any specific command:

1. **Verify every load-bearing claim yourself before acting.** A handed-over manifest/roomservice or a prior analysis may be 90% right. The 10% that's wrong (a remote re-declared, a branch that doesn't exist, a blob set that's missing) is what costs hours. Use `git ls-remote`, `repo manifest`, and raw file fetches to confirm *branches exist*, *paths resolve*, and *files are present* — don't trust, check.

2. **"It's in the source tree" ≠ "it's in the build."** A synced repo, a `config.mk`, a blob — none of it matters unless something **inherits/installs it into the lunched product**. Always trace the inheritance chain and then **grep the built image** (`out/target/product/<device>/...`) to confirm the artifact actually shipped. We hit this twice (JamesDSP orphaned; JamesDSP effect dropped by a config collision).

3. **Fail fast, validate cheap.** Soong analysis and product-config errors surface in ~1–2 min via `m nothing`. Never gamble a 30-min–3-hr compile on an unverified makefile change — run `m nothing` first; it exercises product config + both artifact-path checkers.

4. **Distinguish *environment* failures from *ROM* failures.** Several "build is broken" symptoms were actually the surrounding shell/host environment (harness `grep`/`find` wrappers, `set -u`, missing cookiefile). When a base/reference target (e.g. `lineage_<device>`) fails *the same way* as your custom target, the problem is environmental, not your product.

5. **Prefer changes in files you own.** Put fixes in *your* leaf product makefile (`infinity_<device>.mk`) or your local manifest, not in shared upstream trees that a re-sync can clobber — except when the fix must live in the winning file (e.g. an audio config collision where the upstream file wins; then edit that file and note it as re-sync-fragile).

6. **Run long jobs detached + monitored.** `nohup` wrapper script → `*.log`, plus a completion watcher. Don't block a turn on a multi-hour sync/build; get notified at the terminal state and capture both success and failure signatures.

7. **Read the actual error, not the summary.** The one-line failure ("ninja: build stopped") is useless; the **offending entries** block 30 lines up is the fix. Always pull surrounding context from the log.

---

## 2. Environment: requirements & verification

A modern AOSP/LOS tree needs serious hardware. Verify *before* syncing:

```bash
nproc --all                          # cores (more = faster compile; we had 96)
free -h                              # RAM: 16GB min, 32GB+ comfortable, we had 251GB
df -h .                              # disk: ~300GB per device (250GB source + 150GB out). We had 3.6TB free
for t in repo git git-lfs ccache python3 java make; do command -v $t || echo "$t MISSING"; done
java -version                        # JDK present (AOSP ships its own prebuilt JDK; system one is mostly irrelevant)
lsb_release -d                       # Ubuntu 22.04/24.04 are well-trodden
```

**Reference data point (this build):** 96 cores / 251 GB RAM / 3.6 TB free / Ubuntu 24.04 / all tools present → no host setup needed.

---

## 3. Understanding the resources (do this before touching anything)

For a ROM build you're handed three things: a **ROM manifest**, a **device roomservice/local-manifest**, and a **target device codename**. Map them out:

- **Read the ROM manifest's README** for the exact `repo init` URL/branch, the `lunch` combo format, and the build command. (Infinity-X: `repo init -b 16`, `lunch infinity_$device-$buildtype`, `m bacon`.)
- **Read the manifest's `default.xml`** for the `<default revision=...>` — this tells you the **real base** (e.g. `refs/heads/lineage-23.2`) and the AOSP tag (`<remote name="aosp" revision="refs/tags/android-16.0.0_r4">`).
- **Decode the device stack.** For Pixel 8: codename **shiba**, lives in the **shusky** device tree (shared with husky = 8 Pro), SoC platform tree **zuma**, plus **gs-common** (shared Pixel/Tensor bits) and a prebuilt **kernel** repo. Proprietary blobs live in `vendor/google/<device>`.

### 3.1 Branch alignment (the subtle hazard)

A roomservice cobbled from another ROM often **mixes incompatible branch bases**. You must align the device-side trees to the ROM's platform base. The QPR/branch map for Infinity-X 16:

| Manifest branch | = LineageOS branch | = Android 16 level |
|---|---|---|
| `16-QPR0` | `lineage-23.0` | 16.0 |
| `16-QPR1` | `lineage-23.1` | 16 QPR1 |
| **`16`** | **`lineage-23.2`** | **16 QPR2 (current)** |

**Rule:** put device/SoC/sepolicy trees on the branch matching the ROM platform (here **16.2 / lineage-23.2**); kernel + proprietary blobs go on whatever branch exists and shares the **firmware fingerprint** (here only `16.0` exists, fingerprint `BP4A.260205.001` — same for both branches, so it's the correct match). **Verify branch existence empirically:**

```bash
git ls-remote --heads https://github.com/<maintainer>/<repo> | grep -oE 'refs/heads/16[^ ]*'
git ls-remote --heads https://gitlab.com/<maintainer>/<blobrepo>     # blobs often on GitLab
```

We found: device trees (shusky/zuma) had `16.2`; kernels only `16.0`/`16.1`; **blobs only `16.0`** → so blobs stay 16.0, device trees go 16.2. Drop devices you don't own (we dropped akita = Pixel 8a).

### 3.2 Local-manifest hygiene

- **Do NOT re-declare remotes** that the ROM's `default.xml` already defines (`github`, `gitlab`, `aosp`). Re-declaring throws `remote 'gitlab' already exists`. The handed-over roomservice had this bug — we deleted the `<remote name="gitlab">` line.
- After installing the local manifest, **confirm it parses and resolves** before syncing:
  ```bash
  repo manifest | grep -E "shusky|zuma|shiba|gs-common"   # check revisions + remotes are right
  ```

---

## 4. Sync strategy

```bash
# resilient wrapper: repo sync is resumable, so loop-retry on transient failures
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j16
```

- **`-j16`, not `-j$(nproc)`** when sync health is uncertain — the bottleneck is remote rate-limiting, not CPU. With ~1180 repos, ~75% from `android.googlesource.com`, aggressive parallelism invites `429`/RPC failures. With **authenticated cookies + shallow** (`--depth=1`), even higher is fine.
- **Shallow** (`repo init --depth=1` + `clone-depth=1` in the manifest + `-c`) drastically cuts data and throttling risk.
- Wrap in a retry loop (8 attempts, 30s backoff); each retry resumes. Run detached + watch the log.

---

## 5. Gotchas, ranked by how much time they cost

> Each entry: **Symptom → Root cause → Fix → General lesson.**

### 5.1 The cookiefile hard-gate (blocks sync entirely)

- **Symptom:** `repo sync` exits 126, fetches **0** projects: `GitRequireError: Missing Cookiefile for android.googlesource.com`.
- **Root cause:** Infinity-X ships a **patched `repo`** (`.repo/repo/project.py` ~line 1413) that hard-gates *all* git ops unless `git config --global http.cookiefile` is non-empty. It checks the config value only — **not** the file's contents/existence.
- **Fix (minimum):** `touch ~/.gitcookies && git config --global http.cookiefile ~/.gitcookies` → passes the gate; anonymous AOSP clone works (subject to throttling). **Fix (proper):** generate real cookies at <https://android.googlesource.com/new-password>, append to `~/.gitcookies`. Real cookies raise AOSP quota → no throttling (matters a lot when 75% of repos are AOSP-hosted).
- **Lesson:** Some ROMs patch `repo` itself. When a gate makes no sense, read the patched source to find the *exact* condition — it's often weaker than the scary message implies.

### 5.2 Harness shell wrappers break `lunch` (the nastiest red herring)

- **Symptom:** `lunch <anything>-userdebug` fails with `ugrep: no PATTERN specified` and `error: Cannot locate config makefile for product "<product>-userdebug"` — note it treats the **whole combo string** as the product name. Happens for the **baseline `lineage_<device>` too**, so it's not your product.
- **Root cause:** The interactive shell (here a Claude Code session) injects **shell *functions* shadowing `grep` and `find`** that route through `ugrep`. AOSP's `lunch`/product-config calls bare `grep`; ugrep rejects it; lunch's parsing breaks and never splits product from variant.
- **Diagnose:** `type grep` (is it a function?); `declare -f grep | grep -c CLAUDE_CODE_EXECPATH`; enumerate all wrappers:
  ```bash
  for fn in $(declare -F | awk '{print $3}'); do
    declare -f "$fn" | command grep -q CLAUDE_CODE_EXECPATH && echo "wrapped: $fn"; done
  ```
- **Fix:** `unset -f grep find` in the build shell **before** sourcing envsetup/lunch. The wrappers do **not** export into `make` subprocesses (`bash -c 'type grep'` → `/usr/bin/grep`), so only the direct shell needs it.
- **Lesson:** When a base/reference target fails identically to yours, suspect the **environment**, not the ROM. Shadowed coreutils (aliases or functions for `grep`/`find`/`sed`) silently corrupt AOSP build logic.

### 5.3 `set -u` breaks `envsetup.sh`

- **Symptom:** `build/envsetup.sh: line N: TOP: unbound variable` → `lunch: command not found`.
- **Root cause:** AOSP `envsetup.sh` references unset vars by design. A build wrapper with `set -u` (nounset) aborts the `source` early, so `lunch`/`m` never get defined.
- **Fix:** Never use `set -u` in a script that sources `envsetup.sh`.

### 5.4 Missing ROM product makefile (`infinity_<device>` doesn't exist)

- **Symptom:** Device tree only ships `lineage_<device>.mk` + `aosp_<device>.mk`; `lunch infinity_<device>` has nothing to resolve.
- **Root cause:** The device tree was authored for LineageOS; the ROM brands its lunch combo differently (`infinity_`).
- **Fix:** Create `device/<oem>/<tree>/infinity_<device>.mk` as a thin clone of `lineage_<device>.mk` with two changes — inherit the ROM's common (`vendor/infinity/config/common_full_phone.mk`) and `PRODUCT_NAME := infinity_<device>` — then add it to `AndroidProducts.mk` `PRODUCT_MAKEFILES` (and optionally `COMMON_LUNCH_CHOICES`). **Verify the ROM's `common_full_phone.mk` path exists** (`git ls-remote`/raw fetch) before relying on it. This is also the right home for device-specific build fixes you own (see §5.5, §6).

### 5.5 Artifact Path Requirements — TWO independent checkers

- **Symptom 1 (soong):** `internal error: Device makefile produces files inside .../generic_system.mk's artifact path requirement` at the "analyzing Android.bp" stage. Offending: `system/priv-app/OmniStyle/OmniStyle.apk`.
- **Symptom 2 (kati):** `build/make/core/artifact_path_requirements.mk:31: error` later. Offending: `system/media/bootanimation.zip`.
- **Root cause:** `generic_system.mk` enforces a GSI/Treble whitelist of what may live in the bare `system/` partition. This device build ships ROM assets there. **Two enforcers exist with different rules:** soong (catches `Android.bp` modules) **ignores** `PRODUCT_ENFORCE_ARTIFACT_PATH_REQUIREMENTS := relaxed`; kati (catches copied files) honors it. So `relaxed` alone re-breaks soong.
- **Fix (satisfies both):** allow-list each offender in your leaf product makefile:
  ```make
  PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST += \
      system/priv-app/OmniStyle/% \
      system/media/bootanimation.zip
  ```
  Each checker lists its **complete** offender set at once, so allow exactly those. APR is a **GSI-compatibility lint** — relaxing/allowing it has **zero** functional effect on a real device image.
- **Validate:** `m nothing` runs both checkers in ~2 min.
- **Lesson:** Don't reach for the global "disable enforcement" switch first; it may not even work for one of the two checkers. Allow-listing is deterministic and honored everywhere.

### 5.6 Feature wired in source but dropped from the image (audio config collision)

- **Symptom:** JamesDSP app on-device: *"failed to load jamesdsp.so — please install module and reboot."* (The `.so` is on disk, but the effect isn't registered with the audio framework.)
- **Root cause:** Two `PRODUCT_COPY_FILES` write the **same** destination `/vendor/etc/audio_effects_config.xml`: the SoC tree (`device/google/zuma/common.mk:459`) and `vendor/JamesDSP/config.mk`. The **SoC copy wins** the collision, so JamesDSP's `<library>`/`<effect>` registration is silently dropped. (No build error — at most a warning.)
- **Diagnose (server-side, no device needed):** grep the **built** config:
  ```bash
  grep -i jamesdsp out/target/product/<device>/vendor/etc/audio_effects_config.xml   # empty = dropped
  ```
- **Fix:** Inject the two entries into the **winning** config (`device/google/zuma/audio_effects_config.xml`) — exactly how the maintainer had already added ViPER4Android (`v4a_aidl`):
  ```xml
  <library name="jdsp" path="libjamesdspaidl.so"/>
  <effect name="jamesdsp" library="jdsp" uuid="f27317f4-c984-4de6-9a90-545759495bf2" type="f98765f4-c321-5de6-9a45-123459495ab2"/>
  ```
  (The JamesDSP app attaches the effect to the output mix itself, so registering library+effect is sufficient — no `<postprocess>` entry needed. The `type` UUID lets the AIDL EffectFactory identify a custom effect without a `kUuidNameTypeMap` entry.)
- **Lesson:** When a vendor add-on "just copies a whole config file," it loses on any device that already ships that file. Merge into the winning file instead of overwriting. Always confirm the feature in the **built image**, then on-device.

---

## 6. Wiring & verifying requested features

The user wanted: **(a)** Google's *real* Class-3 face unlock (banking-capable) instead of the ROM's basic one, and **(b)** JamesDSP.

**Methodology — for any "make feature X work" request:**
1. Find what provides it (blobs/packages) and whether anything **inherits** it (`grep -rn "config.mk" device/ vendor/`).
2. Trace the inheritance chain to the lunched product.
3. After build, **grep the built image** to confirm the artifacts shipped.

### 6.1 Google Class-3 face unlock — *was already wired*
- The HAL is the proprietary APEX `vendor/google/shiba` → `com.google.android.hardware.biometrics.face.apex` (the strong/Class-3 implementation), inherited via `shiba-vendor.mk`.
- `device/google/zuma/common.mk` inherits `vendor/google/faceunlock/config.mk`, which (i) sets `TARGET_FACE_UNLOCK_SUPPORTED := false` → **disables the ROM's basic Class-1 face unlock**, and (ii) adds `SettingsGoogleFutureFaceEnroll`, the enroll overlay, and the `biometrics.face` permission.
- **Verification in built image:** the Google face apex present; `SettingsGoogleFutureFaceEnroll` in `system_ext/priv-app`; basic `org.lineageos.faceunlock` **absent**; **`check_vintf` passed** (proves the Google HAL and the AOSP *virtual* face apex don't both claim the `default` instance → real HAL binds). Confirmed working on-device.

### 6.2 JamesDSP — *needed wiring + a fix*
- It was **orphaned**: `vendor/JamesDSP/config.mk` exists but nothing inherited it. Added `$(call inherit-product-if-exists, vendor/JamesDSP/config.mk)` to `infinity_<device>.mk`.
- Then it shipped but didn't load → the audio config collision in §5.6. Fixed there.

---

## 7. Build orchestration (long jobs, detached + monitored)

Pattern used for both sync and build:

```bash
# wrapper script (no `set -u`!); strips harness wrappers; logs everything
#   .staging/run_build.sh:
cd /home/chiranz/infinityx
unset -f grep find 2>/dev/null || true
source build/envsetup.sh
unset -f grep find 2>/dev/null || true
export USE_CCACHE=1 CCACHE_DIR=/home/chiranz/infinityx/.ccache
ccache -M 50G >/dev/null 2>&1 || true
export INFINITY_MAINTAINER=chiranz WITH_GAPPS=false
lunch infinity_shiba-userdebug || { echo "LUNCH FAILED"; echo "BUILD DONE rc=90"; exit 90; }
m bacon -j$(nproc --all); rc=$?
echo "=== BUILD DONE rc=$rc ==="; echo "BUILD_FINAL_RC=$rc"
```

```bash
# launch detached + watch for the terminal state (success OR failure signatures)
nohup bash .staging/run_build.sh > build.log 2>&1 &
# completion watcher greps build.log for: "BUILD DONE rc=|ninja: build stopped|FAILED: out"
```

- **ccache on** → incremental rebuilds are ~10 min vs ~30 min cold.
- A one-config-file change triggers `No need to regenerate ninja file` → only vendor image + repackage rebuild.
- **Cosmetic, ignore:** `Build sandboxing disabled due to nsjail error` (server nsjail quirk); `repo 2.x available / launcher not writable` (system `repo` can't self-update; `.repo/repo` is used anyway).

---

## 8. Post-build verification (don't ship blind)

```bash
P=out/target/product/<device>
ls -lh $P/Project_Infinity-X-*.zip; sha256sum $P/Project_Infinity-X-*.zip

# requested features actually in the image:
find $P/{system,product,vendor,system_ext} -iname "*jamesdsp*"
grep -i jamesdsp $P/vendor/etc/audio_effects_config.xml          # must be present (§5.6)
find $P -iname "*biometrics.face*"; find $P -ipath "*FaceEnroll*"

# firmware identity (see §9):
grep -E "^ro.build.(id|fingerprint|version.security_patch)=" $P/system/build.prop
grep -E "^ro.vendor.build.(fingerprint|security_patch)=" $P/vendor/build.prop
```

Then on-device smoke test: WiFi, data, calls, camera, fingerprint + **the specific features you added**.

---

## 9. Firmware identity: build-ID vs fingerprint vs security-patch (don't confuse them)

Three different identifiers, **designed** to differ on a custom ROM:

| Property | Example | Meaning |
|---|---|---|
| `ro.build.id` / "Build number" | `BP4A.251205.006` | **AOSP source tag** the ROM was compiled from (`build/core/build_id.mk`). Lags Google's latest OTA — normal. |
| `ro.build.fingerprint` | `google/shiba/shiba:16/BP4A.260205.001/.../release-keys` | **Device fingerprint**, set to a real certified Google build → used by Play Integrity. Should match the **blob** level. |
| `ro.build.version.security_patch` (system) | `2026-06-01` | Framework patch level — kept current by the ROM. |
| `ro.vendor.build.security_patch` | `2026-02-05` | Firmware/blob patch level — tied to the proprietary blobs. |

**Build-ID letter = calendar cycle, not Android version:** `B`P4A = 2025 cycle, `C`P1A = 2026 cycle — both Android 16. So Google's "May 2026" stock (`CP1A.260505.005`) is a newer *cycle* than our `BP4A` base. A custom ROM lags because it's built from a pinned source tag + a specific blob set.

**Key correctness rule:** the fingerprint must match the **actual blob/firmware level**, not the newest stock string. Spoofing a newer fingerprint than your blobs/firmware *hurts* Play Integrity (claimed vs attested mismatch). To genuinely move to a newer base you need **all three together**: newer blobs (extracted from the new factory image or published by the maintainer), the matching stock bootloader/radio flashed on the phone, and a re-synced source tag.

---

## 10. Flashing (Pixel 8 / shiba — A/B + `init_boot`, generalizes to recent Pixels)

Build emits raw images alongside the OTA zip: `boot.img init_boot.img dtbo.img vendor_boot.img vendor_kernel_boot.img system/vendor/product/system_ext.img`.

**First install (wipes):**
```bash
fastboot flashing unlock          # wipes
fastboot flash init_boot init_boot.img
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash vendor_boot vendor_boot.img
# reboot to ROM recovery → factory reset → Apply Update → ADB sideload:
adb sideload Project_Infinity-X-*.zip
```

**Update / dirty flash (same version, keeps data):** reboot to recovery → `adb sideload <zip>` → **do NOT factory reset** → reboot. Used to ship the JamesDSP fix without data loss.

- First boot: 3–8 min (ART/dex). Looping boot animation ≠ bootloop.
- `test-keys` warning at boot is normal for self-built/unofficial.
- Bootloop → capture `adb logcat` / `last_kmsg`; most first-build loops are sepolicy denials or a blob/firmware mismatch.

---

## 11. Banking apps (separate from face-unlock class)

Class-3 face unlock makes face usable for `BiometricPrompt`, but banking apps also need **Play Integrity** to *run* on an unlocked bootloader. That's a distinct workstream: a Play Integrity Fix module (KSU/Magisk) + a valid keybox, fingerprint matching the blob level. STRONG/hardware-attested integrity is generally unreachable on an unlocked bootloader; BASIC+DEVICE via PIF is the usual target.

---

## 12. Quick reference — files we created/edited

| File | Why |
|---|---|
| `.repo/local_manifests/roomservice_<device>.xml` | Corrected device manifest (aligned branches, no duplicate remote) |
| `device/<oem>/<tree>/infinity_<device>.mk` | ROM product makefile (clone of lineage_, + JamesDSP inherit, + APR allow-list) |
| `device/<oem>/<tree>/AndroidProducts.mk` | Registered `infinity_<device>` product + lunch choice |
| `device/google/zuma/audio_effects_config.xml` | Added `jdsp` library + `jamesdsp` effect (the winning config — **re-sync-fragile**) |
| `.staging/run_sync.sh`, `.staging/run_build.sh` | Detached, retrying, log-emitting wrappers |

**Re-sync warning:** the `zuma/audio_effects_config.xml` edit lives in a shared upstream tree; a `repo sync --force-sync` can revert it. Re-apply after any destructive re-sync (or move it into a device RRO/overlay you own for permanence).

---

## 13. The debugging loop that solved everything (use this rhythm)

1. **Reproduce cheaply** — `m nothing` for config/analysis errors; targeted grep of the built image for "shipped?" questions.
2. **Read the full error**, not the summary — find the *offending entries* block.
3. **Locate the source** — `grep -rn` across `device/`, `vendor/`, `build/` for the failing symbol/path; `git ls-remote` for "does this branch/file exist."
4. **Decide where the fix belongs** — your leaf makefile (preferred) vs the winning upstream file (when forced).
5. **Validate the fix in isolation** (`m nothing`) before the long build.
6. **After build, verify in the image**, then on-device.

This rhythm turned a stack of cryptic failures into a clean, working ROM. Hand it to the next agent and they'll move much faster.

---

*Generated from the Infinity-X / Pixel 8 (shiba) build session. Device-specific names (`shiba`, `shusky`, `zuma`, `infinity_`) are the worked example — substitute your device/ROM and the methodology holds.*
