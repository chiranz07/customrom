# customrom — Pixel 8 (shiba) custom ROM build notes

Reproducible build notes + artifacts for custom ROMs on the **Google Pixel 8 "shiba"**, captured from working builds (June 2026). Two ROMs built from the same device sources: **Project Infinity-X** and **Project Mist OS** (both Android 16 / lineage-23.2).

## What's here

| File | Purpose |
|---|---|
| **[SHIBA_BUILD_GUIDE.md](SHIBA_BUILD_GUIDE.md)** | **Start here.** Device-specific, copy-paste recipe (Infinity-X worked example): exact commands, full file contents, every problem hit + fix, flashing. |
| **[SOURCES.md](SOURCES.md)** | **All source repos** used (both ROMs) in one reference table — manifests, device/SoC/blob/kernel trees, branches, remotes. |
| [CUSTOM_ROM_BUILD_PLAYBOOK.md](CUSTOM_ROM_BUILD_PLAYBOOK.md) | Generic methodology version (transfers to other ROMs/devices). |
| `staging/roomservice_infinity_shiba.xml` | Infinity-X device local manifest (drop in `.repo/local_manifests/`). |
| `staging/roomservice_mist_shiba.xml` | Mist OS device local manifest (no `vendor/bcr`; Mist ships its own). |
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
