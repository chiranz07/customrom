# customrom — Pixel 8 (shiba) custom ROM build notes

Four ROM builds are documented here, each self-contained:

| ROM | Where | Status |
|---|---|---|
| **Mist-OS 5.0 (Android 17)** | **[`mistos/`](mistos/README.md)** — build guide, full knowledge base (`HANDOFF.md`), per-feature recipes (`FEATURES.md`), per-repo patches, scripts, manifests | **Maintained.** shiba + husky published, both tested on hardware |
| **VoltageOS 6.1 (Android 17)** | **[`voltage/`](voltage/VOLTAGE.md)** — procedure, patches, changelog | **Maintained.** shiba + husky published; vanilla ROM, GmsCompat instead of GApps |
| PixelOS (Android 17) | [`pixelos/`](pixelos/PIXELOS.md) | Built Sept 2026, not maintained |
| Project Infinity-X (Android 16) | this directory (below) | Built June 2026, superseded |

**[ROM_LANDSCAPE_AND_EFFORT.md](ROM_LANDSCAPE_AND_EFFORT.md)** — which other ROMs are actually
buildable for shiba/husky on Android 16 and 17 (verified live, with the method to re-check),
why AlphaDroid 17 and PenguinOS are not options, what running our own ROM would cost, and what
changes when an AI agent maintains it.

Downloads for the maintained ROMs: **https://sourceforge.net/projects/chiranz/files/** —
`mistos/{shiba,husky}/` and `voltage/{shiba,husky}/`, each with an `img/` folder
(boot, init_boot, vendor_boot, vendor_kernel_boot, dtbo). Only the latest build per device is kept.

---

Reproducible build notes + artifacts for **Project Infinity-X (Android 16)** on the **Google Pixel 8 "shiba"**, captured from a working build (June 2026).

## What's here

| File | Purpose |
|---|---|
| **[SHIBA_BUILD_GUIDE.md](SHIBA_BUILD_GUIDE.md)** | **Start here.** Device-specific, copy-paste recipe: exact commands, full file contents, every problem hit + fix, flashing. |
| **[SOURCES.md](SOURCES.md)** | **All source repos** used in one reference table — manifest, device/SoC/blob/kernel trees, branches, remotes. |
| [CUSTOM_ROM_BUILD_PLAYBOOK.md](CUSTOM_ROM_BUILD_PLAYBOOK.md) | Generic methodology version (transfers to other ROMs/devices). |
| `staging/roomservice_infinity_shiba.xml` | Infinity-X device local manifest (drop in `.repo/local_manifests/`). |
| `staging/infinity_shiba.mk` | The ROM product makefile the device tree lacks (→ `device/google/shusky/`). |
| `staging/AndroidProducts.mk.shusky` | `shusky` AndroidProducts.mk with `infinity_shiba` registered. |
| `staging/audio_effects_config.xml.zuma` | `zuma` audio config **with the JamesDSP fix** (→ `device/google/zuma/`). |
| `staging/run_sync.sh`, `staging/run_build.sh` | Detached, retrying sync/build wrappers. |
| `staging/reapply_tree_edits.sh` | Restore the 3 re-sync-fragile tree edits after `repo sync --force-sync`. |

## The 3 Pixel-8 fixes (if you only remember this)

1. **`unset -f grep find`** + **no `set -u`** in the build shell — else `lunch` mis-resolves the product.
2. **`PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST`** for `OmniStyle` + `bootanimation.zip` (two APR checkers; `relaxed` alone won't satisfy soong).
3. **Inject `jdsp`/`jamesdsp` into `device/google/zuma/audio_effects_config.xml`** (the winning audio config) — else JamesDSP "fails to load."

Plus the universal first step: set up **`~/.gitcookies`** or `repo sync` won't even start.

## ⚠️ Notes

- Branch numbers, blob maintainers, and the `BP4A.260205.001` fingerprint are **point-in-time (June 2026)**. Re-verify with `git ls-remote` before a future rebuild — the *methodology* holds, the version strings may move.
- **No secrets in this repo.** `~/.gitcookies` (a Google account token) and any signing keys must be kept **private** — never commit them. This build used default `test-keys`.
