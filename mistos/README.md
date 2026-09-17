# Mist-OS (Android 17) for Google Pixel 8 (shiba) — rebuild guide

Everything needed to reproduce the `MistOS-5.0-Alpha-17.0-MINI-*-shiba-UNOFFICIAL`
builds from scratch, written for whoever (human or AI agent) does the next
Mist-OS update. Read this file top to bottom first; then read `HANDOFF.md`,
which is the full knowledge base (every root cause, dead end and gotcha, ~1400
lines). This README is the *procedure*; HANDOFF.md is the *why*.

Maintainer: chiranz · Releases: https://sourceforge.net/projects/mistos-shiba-unofficial/files/

---

## 0. What this folder contains

| Path | What it is |
|---|---|
| `README.md` | This guide |
| `HANDOFF.md` | Full knowledge base: root causes, verification methods, dead ends, decisions |
| `local_manifests/shusky.xml` | The ROM local manifest (device tree, blobs, JamesDSP, GCam, face unlock) → goes to `.repo/local_manifests/` |
| `local_manifests/kernel_gs.xml` | Kernel local manifest (engstk/gs overlay) — **reference only, the ROM ships the stock kernel** |
| `patches/rom/*.patch` | One `git diff --binary` patch per upstream repo. `MANIFEST.txt` lists the base commit each patch was made against |
| `patches/kernel/*.patch` | Changes made in the separate kernel tree (`~/kernel`) — reference only |
| `files/…` | Plain copies of every *new* or heavily-edited file, in tree-relative paths (same content as the patches; handy when a patch no longer applies cleanly) |
| `scripts/` | Build supervisor, sync retry loops, build-kill helper, patch applier |
| `kernel/` | KSU kernel build artifacts for reference (defconfig fragment, resulting `.config`) |

Binary files (`.apk`, `.img`) are **not** in the patches. The only one that
matters is `device/google/shusky-kernels/boot.img` — see §5.

---

## 1. Host environment that produced the builds

- Ubuntu server, 96 cores / 251 GB RAM, **heavily shared** (load average routinely 300–500, other users exhaust RAM). Everything below is designed around builds getting OOM-killed mid-way.
- ~16 TB disk; the ROM tree is ~450 GB with `out/`.
- Python 3.12, OpenJDK 17 (only needed by build tooling; the ROM build brings its own toolchain), `repo` 2.52 (Shra1V32/git-repo fork), `lz4`, `xmllint`, `debugfs` (e2fsprogs).
- Paths used throughout: ROM tree `~/mistos`, kernel tree `~/kernel`, supervisor scripts in `~`.

---

## 2. Sync the ROM source

```bash
mkdir -p ~/mistos && cd ~/mistos
repo init -u https://github.com/Project-Mist-OS/manifest.git -b 17.0 --git-lfs
mkdir -p .repo/local_manifests
cp <this folder>/local_manifests/shusky.xml .repo/local_manifests/
# retry loop that survives network flakiness:
cp <this folder>/scripts/rom_run_sync.sh ./run_sync.sh && bash ./run_sync.sh
```

The Mist manifest already declares the `github`, `aosp` and `gitlab` remotes
— do **not** redeclare them in the local manifest (repo errors out).

Repos pulled by the local manifest (all pinned by branch, not commit — check
for upstream movement on every update):

| Project | Path | Branch | Purpose |
|---|---|---|---|
| ionutsandroidbuilds/android_device_google_shusky | device/google/shusky | 17.0 | device tree |
| ionutsandroidbuilds/android_device_google_zuma | device/google/zuma | 17.0 | SoC tree |
| ionutsandroidbuilds/android_device_google_shusky-kernels | device/google/shusky-kernels | 17.0 | **prebuilt stock kernel + modules** (this is what ships) |
| TheMuppets/proprietary_vendor_google_shiba (+husky) | vendor/google/shiba | lineage-24.0 | vendor blobs |
| crdroidandroid/proprietary_vendor_google_faceunlock (gitlab) | vendor/google/faceunlock | 16.0 | Google face-unlock enabler |
| ionutgherman/vendor_JamesDSP | vendor/JamesDSP | aidl | JamesDSP (AIDL effects HAL — the only fork that works on this device) |
| ionutsandroidbuilds/proprietary_vendor_google_camera (gitlab) | vendor/google/camera | zuma | real Google Camera |

---

## 3. Apply the changes

```bash
cd ~/mistos
bash <this folder>/scripts/apply_patches.sh <this folder>/patches/rom
```

The script runs `git apply --3way` per repo and reports what failed. For any
failure, open the corresponding `files/…` copy and re-do the change by hand —
every change is explained in `HANDOFF.md`. The patches are grouped below by
what they do, so you know what you're re-applying:

**Required just to compile** (not features):
- `frameworks_base.patch` — `SQLiteTokenizer.java`: port `OPTION_CHECK_BRACKETS` (ContactsProvider needs it). Also SystemUI `TakeScreenshotService` permission for Quick Tap (see below).
- `system_memory_libdmabufheap.patch` — export `BufferAllocator::~BufferAllocator()` (real vendor HAL blobs import it).
- `build_soong.patch` — cosmetic status strings only; drop if it conflicts.

**Product definition** (`device_google_shusky.patch` + `files/device/google/shusky/`):
- `mist_shiba.mk` / `mist_husky.mk` (new): the lunch targets. Sets `TARGET_USES_MINI_GAPPS`, `LINEAGE_BUILD`, `MISTOS_MAINTAINER`, `TARGET_SUPPORTS_QUICK_TAP := true`, fingerprint spoof, APR allowlist, the About-phone prop file.
- `AndroidProducts.mk`: registers the `mist_*` targets.
- `shiba/mist_about.prop` (new): Pixel 8 values for Mist's About-phone card (must be a `.prop` file — `PRODUCT_*_PROPERTIES` truncate values with spaces).
- `device-shiba.mk`: adds `android.hardware.fingerprint.prebuilt.xml` (without it Settings hides fingerprint entirely); removes the inert `ApertureOverlayShiba`.
- `BoardConfigCommon.mk`: super-partition error margin 500 MB → 64 MB (custom additions overflow the stock margin).
- `sepolicy/vendor/*.te` (new): `trusty_apploader_faceauth.te`, `hal_face_default_extra.te` (real face unlock), `audioserver_jamesdsp.te` (JamesDSP), `gpuflag.te` (removes a per-boot `setexeccon` failure; the binary itself is a no-op on zuma — see HANDOFF).

**SoC tree** (`device_google_zuma.patch`):
- `vintf/manifest.xml`: remove the stray `IRemotelyProvisionedComponent/strongbox` declaration (biggest battery fix: 337 servicemanager retries/boot → 1).
- `overlay/*/Android.bp` + `common.mk`: RRO modules renamed with a `Shusky` prefix (name collisions with Mist's own overlays); drop zuma's `default-permissions.xml` (collides with GMS's copy, which is a superset).
- `sepolicy/vendor/hal_camera_default.te`, `gxp_logging.te`, `property_contexts`, `vendor.prop`: real denial fixes + explanatory comments.

**Mist / Lineage vendor layer**:
- `vendor_lineage.patch` — `config/mist.mk`: skip the bundled "Sense" software face unlock for `mist_shiba`/`mist_husky`. **This is the actual Face Unlock fix.**
- `vendor_gms.patch` — `gms_mini.mk` trimmed (but keeps `Velvet`, `GoogleRestorePrebuilt`, `WallpaperPickerGoogleRelease` — all three are load-bearing, see HANDOFF); `pixel_experience_2017.xml` DocumentsUI `PreBootReceiver` disable (restores the Files icon since Files by Google is deliberately excluded); the duplicate `DeviceIntelligenceNetworkPrebuiltAstrea` dir renamed `.disabled`.
- `vendor_pixel-style.patch`, `vendor_extras.patch` — overlay list hygiene.
- `vendor_google_faceunlock.patch` — enable its sepolicy dir, delete a duplicate type, add a missing hwservice type.
- `vendor_google_shiba.patch` / `_husky.patch` — 14 `PRODUCT_COPY_FILES` collisions with GMS removed; dead `abox` init stanza removed.
- `vendor_JamesDSP.patch` — `audio_effects_config.xml` rewritten for the libraries that actually exist on shiba; new `allowlist_james_dsp.xml` power-save allowlist (fixes the screen-off crash).
- `build_make.patch`, `hardware_google_pixel.patch` — remove the virtual biometrics HALs (they hijack the real ones).
- `device_lineage_sepolicy.patch` — `toolbox` may search `/data/adb` (Mist's own root-hiding cleanup script was silently failing).
- `packages_apps_Settings.patch` — face-enroll resource flags; harmless, not the face fix.

Sanity check after applying: `xmllint --noout` every XML you touched (a `--`
inside an XML comment breaks the build), and `repo status` should list the
same projects as `patches/rom/MANIFEST.txt`.

---

## 4. Kernel: use the stock prebuilt (decision, not an accident)

The ROM ships `device/google/shusky-kernels/` **exactly as synced** (Google's
Android 17 factory kernel, `6.1.157-android14-11-…-ab16012876`) with one
change: `boot.img` is re-packed to stamp the OS version / patch level, which
the normal build path skips for prebuilt boot images:

```bash
cd ~/mistos && MK=out/host/linux-x86/bin   # tools exist after the first build; or use any AOSP host tools
$MK/unpack_bootimg --boot_img device/google/shusky-kernels/boot.img --out /tmp/bk
$MK/mkbootimg --header_version 4 --kernel /tmp/bk/kernel --ramdisk /tmp/bk/ramdisk \
  --cmdline '' --os_version 17 --os_patch_level 2026-08-01 \
  --output device/google/shusky-kernels/boot.img
```
Use the tree's current `PLATFORM_SECURITY_PATCH` for `--os_patch_level`.

A self-built KernelSU-Next+SUSFS kernel (`~/kernel`, engstk/gs `blu_spark-17-susfs`
over Google's `android-gs-shusky-6.1-android16` manifest) **builds but
bootloops the phone**. Root cause was never captured; the prime suspect is that
the public kernel manifest's `private/` driver + DTB trees are a year older than
the vendor blobs. Do not put it back into the ROM. Root is done *after*
flashing by installing engstk's prebuilt blu_spark (`gs-susfs` variant, AnyKernel
zip that swaps only `Image.lz4`) — https://github.com/engstk/gs/releases. Full
detail in HANDOFF.md → "KSU kernel bootloop". The `patches/kernel/` and
`kernel/` folders here exist only so that work isn't lost.

---

## 5. Build

```bash
cd ~/mistos
cp <this folder>/scripts/mist_build_supervisor.sh ~/
rm -f ~/mist_build_final_status.txt ~/mistb_attempt*.log
ps aux | grep -E "soong_ui|ninja|mist_build_supervisor" | grep -v grep   # must be empty
fuser ~/mistos/out/.lock                                                  # must be empty
nohup setsid bash ~/mist_build_supervisor.sh 96 > ~/mist_build_supervisor.out 2>&1 < /dev/null & disown
# wait for ~/mist_build_final_status.txt: BUILD_SUCCEEDED | REAL_BUILD_FAILURE attempt=N logfile=... | MAX_ATTEMPTS_EXCEEDED
```

What the supervisor does: `source build/envsetup.sh && lunch mist_shiba-aosp_current-userdebug && mist b -j96`
(= `m installclean && m bacon`), and if ninja dies with `signal: killed` it
waits for RAM and retries instead of reporting a failure. A full build takes
roughly 1.5–3 h on this server; an incremental one ~15–40 min.

Config check without a build (the only form that reliably works under load):
```bash
bash -c 'source build/envsetup.sh >/dev/null 2>&1 && lunch mist_shiba-aosp_current-userdebug >/tmp/l.log 2>&1 && get_build_var PRODUCT_PACKAGES | tr " " "\n" | grep -n ColumbusService'
```
Targeted module builds (`m ColumbusService`, `m vendor_sepolicy.cil`) work the
same way and are the cheap way to test one change.

If you need to stop a build: `bash scripts/killbuild.sh` (do **not** run
`pkill -f mist_build_supervisor` from an interactive command line that itself
contains that string — it kills your own shell; this bit us three times).

---

## 6. Verify the zip before calling it done

Never trust a source edit or the loose `out/` files. Extract the partitions
from the zip's `payload.bin` and inspect *those*:

```bash
cd ~/mistos/out/target/product/shiba
unzip -o -j MistOS-*.zip payload.bin -d /tmp/pl
../../../host/linux-x86/bin/ota_extractor -payload /tmp/pl/payload.bin -output_dir /tmp/pl -partitions boot,product,system_ext,vendor
# kernel identity (banner must be the stock ...-ab16012876 one):
../../../host/linux-x86/bin/unpack_bootimg --boot_img /tmp/pl/boot.img --out /tmp/pl/b
lz4 -d -f /tmp/pl/b/kernel /tmp/pl/b/k && strings /tmp/pl/b/k | grep -m1 "Linux version"
# props and files inside ext4 partitions:
debugfs -R "cat /etc/build.prop" /tmp/pl/product.img | grep -E "ro.mist|ro.mistos.maintainer"
debugfs -R "ls /priv-app" /tmp/pl/system_ext.img | tr -s ' ' '\n' | grep ColumbusService
```
Then `sha256sum` the zip and keep the value with the release.

On the phone after flashing (no root needed):
- Face unlock: `dumpsys face` → `provider: FaceProvider`, `Strength: 15`.
- Files icon present; Quick Tap in Settings → System → Gestures; About phone card populated.
- Clear Calling toggle under Settings → Sound & vibration; after a call, `logcat -d | grep CcaAtom` shows `is_active: 1` (do NOT use `getprop persist.vendor.audio.cca.*` — not shell-readable).
- Now Playing: with a song recognized and the screen locked, song text appears above the indication area; `logcat | grep AmbientIndicationSection` shows "Ambient indication bound to keyguard root view".
- `logcat -d | grep -c "IRemotelyProvisionedComponent/strongbox"` → ~1, not hundreds.
- `getprop` **omits** properties whose SELinux type isn't shell-readable — check `getprop -Z` before concluding anything is "missing".

---

## 7. Publish

SourceForge project **`chiranz`** (https://sourceforge.net/projects/chiranz/files/),
layout per device:
```
shiba/  MistOS-...-shiba-UNOFFICIAL.zip
shiba/img/  boot.img  vendor_boot.img  vendor_kernel_boot.img  dtbo.img
husky/  MistOS-...-husky-UNOFFICIAL.zip
husky/img/  (same four)
```
```bash
# zip
scp -o ServerAliveInterval=30 MistOS-*-shiba-UNOFFICIAL.zip chiranz@frs.sourceforge.net:/home/frs/project/chiranz/shiba/
# img/ files: extract from that zip's own payload so they match the OTA exactly
unzip -o -j MistOS-*-shiba-UNOFFICIAL.zip payload.bin -d /tmp/pl
out/host/linux-x86/bin/ota_extractor -payload /tmp/pl/payload.bin -output_dir /tmp/pl -partitions boot,vendor_boot,vendor_kernel_boot,dtbo
scp /tmp/pl/{boot,vendor_boot,vendor_kernel_boot,dtbo}.img chiranz@frs.sourceforge.net:/home/frs/project/chiranz/shiba/img/
```
Uses the SSH key `~/.ssh/id_ed25519_sourceforge` (registered on the SourceForge
account; `~/.ssh/config` has the host entry). Verify remote sizes with
`sftp … ls -l`. Moving files between folders inside a project works with sftp
`rename`; moving between projects does not (re-upload). No README is wanted in
the file area.

---

## 8. Doing the next Mist-OS update — checklist

1. **Commit or stash first.** As of 2026-09-17 every change is an uncommitted
   working-tree edit (`repo status` shows `*** NO BRANCH ***` for ~18 projects);
   `repo sync` refuses to touch a dirty project. Best: `repo start mist-shiba-local --all`
   then commit per project, so sync rebases and reports real conflicts.
2. `repo sync` (the retry loop script), then `repo status` to see what upstream moved.
3. Re-check the three "load-bearing" things upstream tends to change:
   `vendor/lineage/config/mist.mk` (Sense face-unlock block), `vendor/gms/gms_mini.mk`
   (Quick Tap default, Velvet/Restore/Wallpaper), `device/google/zuma/vintf/manifest.xml`
   (the strongbox RKP line).
4. `device/google/shusky-kernels`: if upstream updated the prebuilt kernel, re-do the
   `boot.img` stamp (§4) — and re-verify the banner in the built zip (§6).
5. If `vendor/google/shiba` blobs moved to a newer build ID, re-run the JamesDSP
   library check (`find out/target/product/shiba/vendor/lib64/soundfx`) and
   re-check `pixelstats_config.json`/boot-patch-level notes in HANDOFF (both are
   symptoms of blob/bootloader version skew and may simply resolve).
6. Build, verify (§6), publish (§7), and update `HANDOFF.md` + this folder.

---

## 9. Known limitations / explicit non-goals (don't re-investigate)

- `ro.boot.boot_patchlevel` empty → RKP/attestation rejected. Bootloader-firmware
  limitation, not fixable from the ROM. Play Integrity is handled with Tricky
  Store + Play Integrity Fix as KernelSU modules.
- StrongBox remote provisioning absent on this blob revision (the retry loop is fixed; the capability isn't restorable).
- Clear Calling: WORKS (the earlier "DCS doesn't exist" note was wrong — it was in `vendor/gms` all along, only listed by `gms_full.mk`).
- Pixel Framework (Google SystemUI/Settings): deferred; best base is `RisingOS-Revived/android_vendor_pixel-framework` branch `sixteen`; no Android 17 branch exists anywhere yet.
- Files by Google: intentionally excluded.
- Signed with AOSP test-keys, `userdebug` (`ro.debuggable=0`). Switching to release keys needs a data wipe.
- Bundled Mist `Updater` points at Mist's official OTA JSON; harmless while no official MINI shiba build is newer than ours, but never accept an OTA from it.

---

## 10. History (what was shipped)

| Build | Notes |
|---|---|
| 20260916-1813 | First booting build (stock kernel; the KSU kernel builds before it bootlooped) |
| 20260917-0904 | Face unlock fix, GCam, StrongBox fix, JamesDSP screen-off fix, DocumentsUI fix (confirmed) |
| 20260917-1036 | + Quick Tap, About-phone card, maintainer; sha256 `229ff6af…89f6` |
| 20260917-1253/1254 | + Clear Calling (DCS, verified on a real call), first Now Playing lock-screen attempt (rendered 0×0: wrong parent) |
| 20260917-1358 | Now Playing via KeyguardSection — song text on lock screen confirmed |
| **20260917-1457** | **Current shiba release.** Now Playing pill centered. sha256 `56a11da23b0265bdd3b5bcf113ebf4c9e5c6e0276748ef68ba070b7281d959c0` |
| **20260917-1514 (husky)** | **First husky build**, same feature set, **untested on hardware**. sha256 `5c6fa94023b869a896dd5479a07b0b535885eccebf5de9657b1ba62b7190c955` |

## 11. husky (Pixel 8 Pro)

Same tree, second lunch target `mist_husky-aosp_current-userdebug`. Differences
from shiba are only in `mist_husky.mk` / `device-husky.mk` / `husky/mist_about.prop`
/ `husky-vendor.mk` (all in the patches). Build with `scripts/mist_build_supervisor_husky.sh`
(separate status file `~/mist_build_final_status_husky.txt`, output under
`out/target/product/husky/`). Both products share the prebuilt kernel repo and
every framework/vendor patch. Nobody has booted the husky build yet — treat the
first report from a Pixel 8 Pro owner as the real test.
