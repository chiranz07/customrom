# Sources — Pixel 8 (shiba) custom ROM builds

All source repositories used to build custom ROMs for the **Google Pixel 8 (`shiba`)**, in one place.
Two ROMs have been built from the same device-side sources (June 2026):

| ROM | Manifest | Branch | Product lunched | Build cmd |
|---|---|---|---|---|
| **Project Infinity-X** | https://github.com/ProjectInfinity-X/manifest | `16` | `infinity_shiba` | `lunch infinity_shiba-userdebug` → `m bacon` |
| **Project Mist OS** | https://github.com/Project-Mist-OS/manifest | `16.2` | `lineage_shiba` | `mistify shiba userdebug` → `mist b` (`m bacon`) |

Both are **Android 16 / lineage-23.2 (QPR2)** based, so they share the same device, SoC, blob, and kernel trees.

---

## Device-side sources (common to both ROMs)

These are pulled via the per-ROM local manifest (`staging/roomservice_*.xml`). Device/SoC/sepolicy trees track **16.2** (QPR2, matches the lineage-23.2 platform); kernel + proprietary blobs track **16.0** (only branch published — same stock firmware fingerprint `BP4A.260205.001`); `gs-common` tracks **lineage-23.2**.

| Path | Repository | Branch | Remote |
|---|---|---|---|
| `device/google/shusky` | ionutsandroidbuilds/android_device_google_shusky | `16.2` | github |
| `device/google/zuma` | ionutsandroidbuilds/android_device_google_zuma | `16.2` | github |
| `device/google/shusky-kernels` | ionutsandroidbuilds/android_device_google_shusky-kernels | `16.0` | github |
| `device/google/gs-common` | LineageOS/android_device_google_gs-common | `lineage-23.2` | github |
| `vendor/google/shiba` | ionutsandroidbuilds/proprietary_vendor_google_shiba | `16.0` | gitlab |
| `vendor/google/husky` | ionutsandroidbuilds/proprietary_vendor_google_husky | `16.0` | gitlab |
| `vendor/google/faceunlock` | crdroidandroid/proprietary_vendor_google_faceunlock | `16.0` | gitlab |
| `vendor/google/camera` | ionutsandroidbuilds/proprietary_vendor_google_camera | `zuma` | gitlab |
| `vendor/google/pixels_extras` | ionutsandroidbuilds/proprietary_vendor_google_pixels_extras | `16.0` | gitlab |
| `vendor/JamesDSP` | ionutgherman/vendor_JamesDSP | `aidl` | github |
| `vendor/bcr` | crdroidandroid/android_vendor_bcr | `16.0` | github |

Remote base URLs: **github** = `https://github.com/`, **gitlab** = `https://gitlab.com/`.

### Device codename map
- **shiba** = Pixel 8 — lives in the shared **shusky** device tree (with **husky** = Pixel 8 Pro). SoC platform = **zuma**.
- Pixel 8a (**akita** / **akita-kernels**) intentionally **omitted** — not the target device.

---

## Per-ROM local-manifest differences (gotchas)

Same device list, but the two ROM manifests handle remotes/duplicates differently — see the `staging/roomservice_*.xml` files:

| | Infinity-X (`roomservice_infinity_shiba.xml`) | Mist OS (`roomservice_mist_shiba.xml`) |
|---|---|---|
| `github`/`gitlab` remotes | predefined by manifest → **don't re-declare** | predefined (via `snippets/mist.xml`) → **don't re-declare** |
| `vendor/bcr` | **included** (ROM doesn't ship it) | **omitted** — Mist ships its own (duplicate-path error otherwise) |
| Product makefile | needs custom `infinity_shiba.mk` (`infinity_` prefix) | **none** — Mist keeps `lineage_` prefix; `lineage_shiba` already exists, rebranded via `vendor/lineage` (= `vendor_mist`, `PRODUCT_BRAND ?= MistOS`) |

---

## Tree edits applied (both ROMs)

- **JamesDSP**: inherit `vendor/JamesDSP/config.mk` in the product makefile **and** register the `jdsp` library + `jamesdsp` effect in `device/google/zuma/audio_effects_config.xml` (the *winning* audio config — otherwise the effect is dropped and the app reports "failed to load jamesdsp.so"). See `staging/audio_effects_config.xml.zuma`.
- **Artifact Path Requirement (APR)** allow-list (GSI lint; functionally inert):
  - Infinity-X: `system/priv-app/OmniStyle/%` + `system/media/bootanimation.zip`
  - Mist OS: `system/lib64/libtensorflowlite%`
- **Google Class-3 face unlock**: already wired by the device tree (`vendor/google/shiba` face HAL apex + `zuma/common.mk` → `vendor/google/faceunlock/config.mk`, which disables the ROM's basic face unlock). No edit needed.

See **SHIBA_BUILD_GUIDE.md** for the full step-by-step with every command and fix.
