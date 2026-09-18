# VoltageOS 6.1 (Android 17) — Pixel 8 / Pixel 8 Pro — Changelog

Maintainer: chiranz · Downloads: https://sourceforge.net/projects/chiranz/files/voltage/

---

## 2026-09-18 — build 3 (shiba `20260918-2104`, husky `20260918-2116`)

Same signing keys as build 2, so this one updates cleanly over it.

### Fixed

- **Face unlock is now the real Class-3 Google one.** Builds 1 and 2 shipped Voltage's bundled
  Megvii/Sense face unlock, which registered a software provider and stopped Android from ever using
  the real Pixel face HAL sitting in the vendor blobs. That meant weaker, non-banking-capable face
  unlock. Verified in the image: the software app and its `ro.face.sense_service` property are gone,
  the real face HAL apex is present, and the face feature declaration is kept so the Settings entry
  still appears.

### Not included, deliberately

- **No app store is bundled.** This ROM's GmsCompat (sandboxed Play) expects GrapheneOS's Apps store,
  but GrapheneOS asks that other systems not redistribute their apps or rely on their servers, and
  that is their call. To get Google Play: install the Apps store yourself from
  https://github.com/GrapheneOS/AppStore/releases, then install Play services and Play Store through
  it. Note GmsCompat also uses that store to refresh its own compatibility config, so without it,
  fixes for newer Play versions won't reach you. The alternative is flashing a GApps package —
  mutually exclusive with GmsCompat, pick one.

### Corrections to build 2's notes

- The reported **recovery failure was tester error** — recovery works. It was never a ROM issue.
- Battery stats are **not** missing rail-level attribution; that claim was wrong. The PowerStats HAL
  is declared by the vendor blobs and runs fine.

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

- **eSIM needs GApps.** The full Pixel eSIM stack is in the build, but Google's eSIM app can't complete
  its backend calls without Play services. Untested with GApps — please report if you try it.
- **GmsCompat and flashed GApps are mutually exclusive.** Use sandboxed Play *or* flash GApps, not both.
- RCS messaging services don't start.
- Neither build has been confirmed booting by the maintainer; Pixel 8 Pro (husky) is untested hardware.

---

## 2026-09-18 — build 1 (shiba `20260918-0808`, husky `20260918-0848`)

First VoltageOS 6.1 build for shiba/husky, from VoltageOS manifest branch `17` on LineageOS
`lineage-24.0` device trees with stock CP2A kernel prebuilts.

Tester report (Pixel 8 Pro): ROM boots, calls, SMS, wifi and location all work. GApps would not install
and fingerprint was missing — both root-caused and fixed in build 2. (A recovery failure was also
reported at the time; it turned out to be tester error, not a ROM issue.)

Vanilla ROM — no GApps, GmsCompat (sandboxed Google Play) instead, Launcher3QuickStep, Aperture camera,
Voltage FaceUnlock, Etar, Seedvault, GameSpace.
