# Source trees used for the 2026-09-17 builds (reference copies)

Full working-tree snapshots **with every Mist-OS shiba/husky edit applied** (i.e. the
pinned upstream commit + `../patches/rom/*.patch`), `.git` stripped:

| Folder | Upstream | Pinned commit (see `../reference/source-pins/`) |
|---|---|---|
| `device/google/shusky` | ionutsandroidbuilds/android_device_google_shusky (`17.0`) | in `mistos-manifest-snapshot-20260917.xml` |
| `device/google/zuma` | ionutsandroidbuilds/android_device_google_zuma (`17.0`) | " |
| `vendor/google/faceunlock` | crdroidandroid/proprietary_vendor_google_faceunlock (`16.0`, gitlab) | " |
| `vendor/JamesDSP` | ionutgherman/vendor_JamesDSP (`aidl`) | " |
| `mist-manifest/` | Project-Mist-OS/manifest (`17.0`) + our `local_manifests/shusky.xml` | `mist-manifest-repo-commit.txt` |

**Not copied (too large for git; public and pinned by exact commit in the snapshot):**
- `device/google/shusky-kernels` (138 MB of prebuilt kernel + modules) — ionutsandroidbuilds/android_device_google_shusky-kernels `17.0`. Only our change there is the re-stamped `boot.img` (README §4).
- `vendor/google/shiba`, `vendor/google/husky` (1.4 GB each) — TheMuppets `lineage-24.0`.
- `vendor/gms` (3 GB) — Mist-OS's own GMS repo; our edits are in `../patches/rom/vendor_gms.patch` and `../files/vendor/gms/`.
- `vendor/google/camera` (441 MB) — ionutsandroidbuilds/proprietary_vendor_google_camera `zuma`.

**To reproduce the exact tree:** `repo init` as in the README, then
`repo sync -m <path-to>/mistos-manifest-snapshot-20260917.xml` (or copy it to
`.repo/manifests/` and `repo init -m`), which checks out every one of the 1,247
projects at the exact commit used. The kernel tree equivalent is
`kernel-manifest-snapshot-20260917.xml` (82 projects; the KSU kernel built from it
bootloops — see HANDOFF).
