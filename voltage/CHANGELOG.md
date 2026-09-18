# VoltageOS 6.1 (Android 17) — Pixel 8 / Pixel 8 Pro — Changelog

Maintainer: chiranz · Downloads: https://sourceforge.net/projects/chiranz/files/voltage/

---

## 2026-09-18 — build 2 (shiba `20260918-1629`, husky `20260918-1659`)

**⚠️ Clean flash required.** This build is signed with a different key set than `0808`/`0848`
(the previous keys were lost with the build server). Dirty-flashing over build 1 will not work.

### Fixed

- **GApps can now be installed.** Build 1 sized every partition to fit its contents exactly, so any
  GApps package failed with "no space left on device" no matter which recovery was used. There is now
  **1134 MB free on product, 92 MB on system, 91 MB on system_ext** — enough for any package.
  (Cause: the device tree's "reserve space for gapps" hook pointed at a LineageOS path that does not
  exist in a Voltage tree, so it silently did nothing.)
- **Fingerprint works.** Build 1 ran the real Goodix fingerprint hardware but never told Android the
  device *has* a fingerprint sensor, so Settings hid the entire fingerprint section.
- **Removed the virtual fingerprint/face HALs**, which registered fake biometric devices alongside the
  real Goodix sensor and the real Google face HAL.
- **Three SELinux denials** silenced/fixed at boot: GXP logging (15 per boot), camera bokeh directory
  creation (10 per boot), and a face-HAL metadata read.
- **`init_boot.img` is now published** in the `img/` folders. It was missing from build 1 — only
  relevant if you flash images manually instead of sideloading the zip.
- **`boot.img` is now stamped** with the correct OS version (17) and security patch level (2026-09).

### Unchanged on purpose

- All Pixel Google blobs are still included — Android System Intelligence, AICore, Device Intelligence,
  Hotword ("Hey Google") enrollment, Now Playing and Pixel Camera Services. They do nothing useful
  without GMS, but they come back to life the moment you flash GApps, which is the assumed setup.

### Known issues

- **Recovery does not boot** (hangs on the Google logo). Under investigation — the recovery image
  itself looks complete, so we need on-device information. Workaround: flash a third-party recovery.
  If you hit this, please report: does `adb devices` see anything while it's stuck, and are you on
  stock CP2A firmware? (A ROM zip never updates the bootloader/radio.)
- **eSIM needs GApps.** The full Pixel eSIM stack is in the build, but Google's eSIM app can't complete
  its backend calls without Play services. Untested with GApps — please report if you try it.
- **GmsCompat and flashed GApps are mutually exclusive.** Use sandboxed Play *or* flash GApps, not both.
- RCS messaging services don't start.
- Battery stats are missing rail-level power attribution (PowerStats HAL not declared in VINTF).
- Neither build has been confirmed booting by the maintainer; Pixel 8 Pro (husky) is untested hardware.

---

## 2026-09-18 — build 1 (shiba `20260918-0808`, husky `20260918-0848`)

First VoltageOS 6.1 build for shiba/husky, from VoltageOS manifest branch `17` on LineageOS
`lineage-24.0` device trees with stock CP2A kernel prebuilts.

Tester report (Pixel 8 Pro): ROM boots, calls, SMS, wifi and location all work. Recovery does not boot.
GApps would not install. Fingerprint appeared to be missing (root-caused in build 2).

Vanilla ROM — no GApps, GmsCompat (sandboxed Google Play) instead, Launcher3QuickStep, Aperture camera,
Voltage FaceUnlock, Etar, Seedvault, GameSpace.
