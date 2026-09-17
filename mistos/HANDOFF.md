# Handoff: Mist-OS Pixel 8 (shiba) ROM Build — Comprehensive Knowledge Base

This document consolidates everything learned across the full build/debug
session for this ROM (2026-09-16 to 2026-09-17, ~24 hours of active work).
Read this fully before touching anything on a future update. **It corrects
real mistakes in an earlier draft of this same file** — most importantly,
an earlier version of this document claimed the Face Unlock fix was a
Settings.apk resource flag. That fix was harmless but **irrelevant to the
actual bug**; the real root cause was something else entirely (see below).
Trust this version, not memory of an earlier one.

## Goal

Build **Project Mist-OS** (Android 17, branch `17.0`) for **Google Pixel 8
(shiba)** only — user explicitly narrowed scope to shiba partway through
(not Pixel 8 Pro/husky, even though the `shusky` device tree covers both,
and most fixes in this document apply equally to husky since the trees are
shared — just not independently verified on husky hardware).

Requested features and their final state:
- Custom kernel: `blu_spark-17-susfs` = **KernelSU-Next + SUSFS** — DONE, confirmed
- Minimal GMS (not full bloat) — DONE, but see the GMS section below: "minimal" repeatedly turned out to have cut things that were actually load-bearing
- Real Google Face Unlock (Class-3/banking-capable) — DONE, confirmed working, `BIOMETRIC_STRONG`
- Real Pixel fingerprint — DONE, confirmed working
- Now Playing — DONE (via TheMuppets' vendor blobs, not independently re-verified this session but no reason to suspect regression)
- JamesDSP (system-wide audio DSP/EQ) — DONE, confirmed working, including a real device-specific config bug fixed
- Real Google Camera (GCam) — DONE, confirmed working (added this session; wasn't originally in scope but requested and delivered)
- Clear Calling (best-effort) — **DROPPED by user**, do not chase it
- Play Integrity — explicitly **out of scope**, user handles separately (uses Play Integrity Fix + Tricky Store as KernelSU modules)
- Pixel Framework (real Google SystemUI/Settings, not just RRO theming) — **deliberately deferred**, see dedicated section below

User wants this **built to completion autonomously** — keep going through
errors, fix them, don't stop to ask unless genuinely blocked on a decision
only they can make (destructive actions, signing keys, flashing/testing,
or anything touching bootloader/radio partitions).

**New priority stated late in this session, apply going forward:** near-zero
crashes and battery-life optimization specifically. Reframes prioritization
from "is it broken?" to "does it cost a wakelock/CPU wakeup?" — a permanent
retry loop or a crash-restart cycle matters more than a cosmetic log line
even if neither is user-visible.

## Locations

- ROM source tree: `~/mistos` (`.repo/local_manifests/shusky.xml` has the pins — see "Reference repos" section for the full current list)
- Kernel source tree: `~/kernel` — built via Bazel Kleaf, entirely separate from the ROM's own build system
- Kernel build output: `~/kernel/out/shusky/dist/` (boot.img, dtbo.img, all `.ko` modules, `.config`, etc.)
- Build supervisor scripts: `~/mist_build_supervisor.sh` (ROM) and `~/kernel_build_supervisor.sh` (kernel)
- Claude's persistent memory for this project: `~/.claude/projects/-home-chiranz814-mistos/memory/` (`mistos_rom_build.md`, `mistos_build_ops.md`)
- This file: `~/mistos/HANDOFF.md` — read it fully before starting a new session on this build

## Git state: NOTHING IS COMMITTED — read this before any `repo sync`

As of 2026-09-17, every change described in this document is an
**uncommitted working-tree modification on a detached HEAD** (`repo status`
shows `*** NO BRANCH ***` for all 22 touched projects). Consequences:

- `repo sync` **refuses to update a project with modified tracked files**
  (it errors out for that project and moves on) — so a Mist update sync
  will partially fail until these are either committed on a local branch
  or stashed. Untracked new files (`mist_shiba.mk`, the new `.te` files,
  `allowlist_james_dsp.xml`, the `.disabled` Astrea dir) survive a sync
  untouched unless upstream adds a file with the same name.
- A full backup of every diff (including untracked files, excluding the
  binary `boot.img`) was exported on 2026-09-17 to
  **`~/mistos_patches_20260917/`** — one `git diff --binary`-style patch
  per project, plus `MANIFEST.txt` (base commit hash + `--stat` per
  project), a copy of `.repo/local_manifests/shusky.xml`, and a copy of
  this file. Apply with `git -C <project> apply ~/mistos_patches_20260917/<project>.patch`.
  Note `device/google/shusky-kernels/boot.img` is NOT in the patches —
  regenerate it via the kernel copy step + the `mkbootimg` repack in the
  boot-patch-level section.
- **Recommended before the next update:** `cd ~/mistos && repo start
  mist-shiba-local --all` (creates a local branch in every project), then
  commit each dirty project (`repo forall -c 'git add -A && git commit -q
  -m "mist_shiba: local changes" || true'`). No git identity is configured
  on this server (`git config --global user.name/email` are unset) — set
  one or use `-c user.name=... -c user.email=...`. With changes on a
  local branch, `repo sync` rebases them onto the new upstream and reports
  real conflicts instead of silently refusing.

## Source patches required just to COMPILE (not feature fixes — the tree won't build without them)

These three edits sit outside the device/vendor trees and were never
written up in the first draft of this document. They are required to get
a clean build at all on this tree revision; if a future sync makes them
conflict, check whether upstream fixed the underlying issue before
re-applying:

1. **`frameworks/base/core/java/android/database/sqlite/SQLiteTokenizer.java`**
   — `ContactsProvider`'s `SelectionBuilder` references
   `SQLiteTokenizer.OPTION_CHECK_BRACKETS` (an AOSP SQL-injection guard:
   unbalanced-bracket checking), which landed in `TelephonyProvider`'s
   bundled tokenizer copy but was never backported to the shared
   framework class in this tree → hard compile error. The real upstream
   implementation was ported into the framework class (adds
   `OPTION_CHECK_BRACKETS`, bracket-level tracking, a `@Nullable`
   checker, and fixes two `options &= ...` typos to `options & ...`).
2. **`system/memory/libdmabufheap/BufferAllocator.{cpp,h}`** — two real
   TheMuppets vendor prebuilts (`android.hardware.audio.service-aidl.aoc`,
   `android.hardware.contexthub-service.generic`) fail Soong's ELF ABI
   check because they import `BufferAllocator::~BufferAllocator()` from
   `libdmabufheap.so`, but the destructor was inline in the header (hidden
   under `-fvisibility-inlines-hidden`). Moved the destructor out-of-line
   so the symbol is exported.
3. **`build/soong/ui/build/rbe.go`** — cosmetic only: three status strings
   (`"Starting rbe..."` → `"Starting ninja..."`, an error-message wording
   change). No functional effect; safe to revert if it ever conflicts.
   Origin unclear (no rationale recorded in any session transcript).

## Current state (as of 2026-09-17, end of this session)

**KERNEL STATUS — READ THIS, the earlier text in this file was misleading.**
The ROM currently ships the **STOCK ionutsandroidbuilds prebuilt kernel**
(`6.1.157-android14-11-g14047afecd8b-ab16012876`, no KernelSU/SUSFS) —
**on purpose**. The KernelSU-Next+SUSFS kernel in `~/kernel/out/shusky/
dist/` (banner `...-g3240d8f38125-dirty`, `CONFIG_KSU=y`) was built
successfully on 2026-09-16 14:17 and **bootlooped on the real Pixel 8 every
time it was flashed** (several attempts, via OrangeFox and RisingOS
recovery). Switching the build back to the stock prebuilt kernel (the
`...-20260916-1813` build) is what made the device boot; the tree was
then deliberately left with only `boot.img` modified in
`device/google/shusky-kernels/` (repacked from the stock `Image.lz4` with
the os_version/patch-level stamp). The "why it bootloops" investigation
was promised at the time but never done — see the "KSU kernel bootloop"
section below for what is known.

**Trap this caused on 2026-09-17:** a fresh review read the `-dirty`
banner rule + "copy step must always be redone" + the absence of KSU in the
shipped kernel as "the copy step was forgotten", performed the copy, and
launched a build — which would have shipped the bootlooping kernel again.
The user caught it. The copy was reverted (`git checkout -- .` + `git
clean -f '*.ko'` in `device/google/shusky-kernels/`, then the stock
`boot.img` re-stamped) and the build killed. **Do not copy `dist/` into
`device/google/shusky-kernels/` again until the bootloop is actually root-
caused and a test kernel has been verified to boot** (`fastboot boot
<boot.img>` is the safe way to test a kernel without flashing it).

**END-OF-DAY STATE 2026-09-17 (authoritative; later sections carry the detail):**
- **Published (SourceForge project `chiranz`):** shiba `...-20260917-1457`
  (sha256 `56a11da23b0265bdd3b5bcf113ebf4c9e5c6e0276748ef68ba070b7281d959c0`),
  husky `...-20260917-1514` (sha256
  `5c6fa94023b869a896dd5479a07b0b535885eccebf5de9657b1ba62b7190c955`,
  **untested on hardware**), each with `img/` (boot, vendor_boot,
  vendor_kernel_boot, dtbo from the zip's payload).
- **Verified on the user's Pixel 8 today:** real Face Unlock, fingerprint,
  Google Camera, wallpaper picker, JamesDSP (+ screen-off fix), DocumentsUI
  icon, Quick Tap (ColumbusService), About-phone card, Clear Calling (DCS,
  active 428 s on a real call), Now Playing song text on the lock screen
  (Pixel ambient indication ported via KeyguardSection, centered), tap/lift
  to check phone with haptic toggle, StrongBox retry-loop fix, gpuflag
  domain. Kernel is the stock prebuilt; root via blu_spark r271 is the
  user's separate step.
- **Not done / parked:** Pixel Framework (SystemUIGoogle/SettingsGoogle),
  self-built KSU kernel (bootloops), release-key signing, committing the
  ~20 dirty repos on a local branch (patch backup + GitHub copy exist).
- Docs + patches: https://github.com/chiranz07/customrom/tree/main/mistos

**Confirmed working on-device by the user or their live-device debugging agent:**
- Boot (stock prebuilt kernel; no root — the KSU kernel is a separate, unfinished project)
- Real Pixel fingerprint
- JamesDSP (AIDL, both the driver-loading issue and a device-specific config bug — see Audio section)
- Real Google Face Unlock, `BIOMETRIC_STRONG`, real Google AIDL HAL (not a software hijack — see Face Unlock section)
- Real Pixel wallpaper app (`WallpaperPickerGoogleRelease`)
- Real Google Camera
- StrongBox VINTF retry-loop fix (337 occurrences/boot → 1, ~84% reduction in total init error lines — the single biggest battery/wakelock win found this session)
- JamesDSP screen-off crash fix (ROM-level power-save allowlist, survives a full `/data` wipe)

**Fixed and rebuilt, on-device confirmation pending as of this writing:**
- DocumentsUI file-manager launcher icon (see dedicated section — this took three attempts to actually root-cause correctly, read it before touching this again)

**Confirmed genuinely unfixable from the ROM build side, don't re-attempt:**
- Boot patch level / hardware attestation (`ro.boot.boot_patchlevel` stays empty) — root cause is the physical bootloader firmware, which this ROM doesn't build or reflash. See "Boot patch level" section for the full, exhaustive investigation — don't repeat it.
- StrongBox actual attestation functionality (the retry-loop *symptom* is fixed; the underlying capability is still absent because the vendor blob's own service never registers it)
- Clear Calling — dropped by user; full root-cause mapping preserved below for reference only
- Pixelstats vendor config mismatch, missing `audiometrics/speaker_version` sysfs node — both are symptoms of the same vendor-blob-version-skew issue as boot patch level, not independently fixable

**Deliberately not attempted, a future session's call:**
- Pixel Framework (real SystemUI/Settings source, not RRO overlay) — see dedicated section
- Vendor blob resync to match platform version — see "The version-skew root cause" section; this is one big decision that would likely resolve several symptoms at once, not something to do piecemeal

## How to build

### The `mist b` / config validation cycle

```bash
cd ~/mistos
source build/envsetup.sh
lunch mist_shiba-aosp_current-userdebug   # 3-part combo required; plain mist_shiba-userdebug fails
m nothing        # config validation only, catches collisions fast
mist b -j<N>     # the real build: m installclean && m bacon -j<N>
```

**Important gotcha about `lunch`/`get_build_var` reliability:** on this
heavily shared server, `lunch mist_shiba-aosp_current-userdebug` and
`get_build_var` calls can **intermittently and non-deterministically fail**
under load with `error: No release config set for target` even with the
exact correct combo string — this is **not a real config problem**,
confirmed repeatedly by retrying the identical command minutes later and
having it succeed, and by full builds succeeding reliably via the
supervisor script using the exact same combo. Don't chase a phantom config
bug if `get_build_var` fails once; either retry, or just trust a full build
run as the ground truth (which is what the supervisor script does anyway).

**What actually worked for `get_build_var` under load 400+ (2026-09-17):**
six back-to-back attempts of `source ... && lunch ... && get_build_var`
directly in the tool shell all failed with the phantom release-config
error, while the supervisor script's form succeeded first try:
```bash
bash -c 'source build/envsetup.sh >/dev/null 2>&1 && lunch mist_shiba-aosp_current-userdebug >/tmp/lunch.log 2>&1 && get_build_var PRODUCT_PACKAGES | tr " " "\n" | grep -n ColumbusService'
```
Use the `bash -c '...'` wrapper form for config checks; it's what the
supervisor uses too.

**Bash tool gotcha:** each Bash tool call is a separate shell process.
`source build/envsetup.sh`, `lunch ...`, and any subsequent `get_build_var`
calls must all happen within the **same** Bash tool invocation — functions
defined by `envsetup.sh` do not persist to a later, separate Bash call.

### Use the resilient supervisor scripts, not raw commands

This is a **heavily shared multi-tenant server** (96 cores / 251GB RAM,
dozens of concurrent users). Load average routinely sits at 90–500+, and
memory/swap gets exhausted from OTHER users' processes. Both the ROM and
kernel builds get killed by system-wide memory pressure fairly often,
mid-build, without warning.

**Always launch builds via the supervisor scripts**, which distinguish a
real compile/config error (stop, needs a fix) from a premature kill (retry
automatically, waiting for memory headroom first):

```bash
cd ~/mistos
rm -f ~/mist_build_final_status.txt ~/mistb_attempt*.log ~/envsetup_attempt*.log ~/lunch_attempt*.log
# confirm nothing else is already running first:
ps aux | grep -E "mist_build_supervisor|soong_ui|ninja" | grep -v grep
fuser ~/mistos/out/.lock
# then launch:
nohup setsid bash ~/mist_build_supervisor.sh 96 > ~/mist_build_supervisor.out 2>&1 < /dev/null &
disown
```

Then watch for `~/mist_build_final_status.txt` to appear
(`BUILD_SUCCEEDED`, `REAL_BUILD_FAILURE attempt=N logfile=...`, or
`MAX_ATTEMPTS_EXCEEDED`). Same pattern for `~/kernel_build_supervisor.sh`
for kernel rebuilds.

**A `FAILED:` line in a build log is not automatically a real compile
failure.** Check for `ninja failed with: signal: (killed|terminated)`
FIRST — an OOM-killed ninja produces its own misleading `FAILED: ... error:
action cancelled when ninja exited` block that looks identical to a genuine
compile error at a glance. The supervisor script already checks for this
signature before treating any `FAILED:` line as real; if you ever bypass
the supervisor, check this yourself before reporting a "real" failure.

### Monitoring gotcha: use the `Monitor` tool, not `Bash run_in_background`

A `Bash run_in_background` polling loop gets killed by the harness's own
low-memory protection roughly every 60–90 seconds when this server is under
heavy pressure — **this only kills the monitor, not the actual detached
build** (which is `setsid nohup`'d and survives independently). Don't
misread a killed monitor as a dead build. A costly mistake was made early
in an earlier session: checking for the build process 5 seconds after
launching it, finding nothing (because `soong_ui` hadn't forked yet), and
concluding it had died — then launching a SECOND competing build that
raced the first one over `out/.lock`. Always check `fuser
~/mistos/out/.lock` and give real elapsed-time margin before concluding a
build died.

Use the `Monitor` tool for the "wait for build completion" pattern instead:

```
Monitor({
  command: "until [ -f ~/mist_build_final_status.txt ]; do sleep 20; done; cat ~/mist_build_final_status.txt",
  description: "mist_shiba build supervisor final status",
  timeout_ms: 1800000
})
```

### Verifying a build artifact — go past the loose `out/` directory

**Established, load-bearing methodology this session:** never trust a
source edit alone, and don't even fully trust the loose files in
`out/target/product/shiba/` — verify the actual **packaged, flashable
artifact**. This ROM ships as an A/B seamless-update OTA zip (`payload.bin`
inside, Chrome-OS-style update_engine format), not raw partition images in
the zip. The loose `out/` directory and the packaged `payload.bin` are
generated by genuinely separate build steps and *can* diverge in principle
(in every case actually checked this session they matched, but the
methodology to check is essential when there's an unexplained
build-vs-device discrepancy):

```bash
# Extract payload.bin from the flashable zip:
unzip -o -j <zip> payload.bin -d <scratch_dir>

# Extract a specific partition's raw image straight out of the payload
# (this is the ACTUAL bytes update_engine would write to the device):
out/host/linux-x86/bin/ota_extractor -payload <scratch_dir>/payload.bin \
    -output_dir <out_dir> -partitions vendor,boot,init_boot,vendor_boot

# Then inspect it the same way you'd inspect any other image, e.g.:
debugfs -R "cat /build.prop" <out_dir>/vendor.img   # ext4 partitions
out/host/linux-x86/bin/unpack_bootimg --boot_img <out_dir>/boot.img   # boot-style images
out/host/linux-x86/bin/avbtool info_image --image <out_dir>/boot.img # AVB footer + custom Props + rollback index
```

A raw `sha256sum` mismatch between the loose `out/` version and the
payload-extracted version of the same partition does **not** by itself
prove a content difference — it's commonly explained by AVB
footer/padding placement differing between the two packaging paths. The
decisive test is inspecting actual filesystem/header content, not the raw
file hash.

AVB footers carry **three independent, separately-checkable things**, and
all three can diverge independently:
1. The plain `mkbootimg` header fields (`os_version`/`os_patch_level`), queryable via `unpack_bootimg`.
2. A rollback index (a raw integer that's often literally a Unix
   timestamp encoding a security-patch date at UTC midnight on the 1st of
   that month — decode with `date -u -d @<value>`), via `avbtool info_image`.
3. Arbitrary custom string `Prop:` entries (e.g.
   `com.android.build.boot.security_patch`), also via `avbtool info_image`.

This session found the header field AND the rollback index both correctly
stamped, yet the actual runtime `ro.boot.*` property was still empty —
because the true authoritative source turned out to be the closed
bootloader firmware's own internal logic, which reads from none of the
three things a ROM build can directly control (see "Boot patch level"
section).

### Property-visibility gotcha — do not repeat this mistake

**This caused a multi-hour false-positive investigation this session** and
is worth internalizing as a standing rule: `getprop` run as unprivileged
shell **silently omits** any property whose SELinux context isn't
shell-readable. It does not show it as empty — it doesn't appear in the
output at all. Before ever concluding a property is "missing" or "not
set" from a `getprop`/`adb shell getprop` check:

1. Check the property's SELinux context type with `getprop -Z` (or by
   grepping `plat_property_contexts`/`vendor_property_contexts` for the
   relevant prefix).
2. Check whether that *type* is shell-readable at all, by counting how
   many OTHER properties of the same type/context are visible in the same
   dump. If it's zero across the board for that context, absence from
   `getprop` proves nothing — it's a measurement artifact, not evidence.
3. Only treat absence as real evidence when the context is confirmed
   generally shell-readable (e.g. `bootloader_prop`, which had 50+ other
   genuinely visible properties in the same dump when this distinction
   mattered) — a specific property missing from an otherwise-populated,
   readable context IS meaningful.

This exact mistake produced an entire false "the whole custom
`persist.vendor.*` block is silently failing to apply" investigation this
session that consumed real time across multiple build-vs-device
comparisons — the properties were correctly set the entire time, just
invisible to unprivileged `getprop` (`vendor_audio_prop`,
`vendor_default_prop`, etc. are simply not shell-readable types).

Related: property **read** denials (`avc: denied { read } ... tclass=file
... dev="tmpfs"`) structurally **cannot** carry the literal property name
being requested — the kernel only knows which properties-tmpfs *backing
file* (one per SELinux context) was denied, not which specific key within
it a process wanted. Property **set** failures (init log lines like
`Unable to set property 'foo.bar' ...`) DO carry the literal name, because
init logs it itself before failing. Don't expect a raw `avc:` read-denial
line to ever hand you a property name — if you need one, the app's own
APK has to be decompiled to find candidate keys it reads, then
cross-referenced against `property_contexts` to find the one with no
entry (the actual fallthrough-to-`default_prop` candidate).

## The version-skew root cause (read this before chasing several individually-looking bugs)

Late in this session, four apparently-separate symptoms turned out to be
the same root cause: **the vendor blobs, radio firmware, and bootloader
are all from an OLDER baseline than the platform build targets.** Confirmed
version chain, oldest to newest:

1. Bootloader (ABL): `ripcurrent-17.0-15199481`
2. Radio/modem: `g5300i-260317-260505-B-15346003`
3. Vendor blobs: `CP2A.260605.016` (June 2026) — this is `ro.vendor.build.id`, and was also found baked directly into `boot.img`'s own AVB custom `Prop: com.android.build.boot.fingerprint`
4. Platform (this ROM's own build): `CP2A.260805.005` (August 2026) — note the device's `ro.build.fingerprint` is **spoofed** to show this value; it does not by itself prove blob vintage, don't use it as an extraction target

Confirmed symptoms of this skew (do not treat these as independent bugs to
patch one at a time):
- **Boot patch level / attestation** — see dedicated section. Bootloader-level, unfixable from ROM build.
- **StrongBox RKP never registers** — the citadel keymint blob has the RKP implementation class compiled in (confirmed via `strings` showing `RemotelyProvisionedComponentDevice` constructor symbols), but the blob's own authoritative VINTF fragment never declares it available, so it's never registered. Fixed the *symptom* (a permanent retry loop) by removing our own tree's stray, incorrect VINTF declaration — see StrongBox section.
- **Pixelstats vendor config shape mismatch** — `vendor/google/shiba/proprietary/vendor/etc/pixelstats_config.json` has `DisplayStatsPaths` with only 4 entries where the shipped `pixelstats-vendor` binary expects 10, and is missing `DSIErrorStatsPaths`/`DisplayRecoveryStatsPaths`/`DpuStatsPaths` keys entirely (binary expects 2/4/4). Confirmed by directly parsing the JSON, not just log correlation. Telemetry-only impact, not independently fixable without correct device-specific sysfs paths we don't have.
- **Missing `audiometrics/speaker_version` sysfs node** — referenced by pixelstats but genuinely absent on this blob revision, even though sibling nodes in the same directory (`cca`, `cca_count_read_once`) exist.

**The one real decision this implies:** should the vendor blobs (and
possibly bootloader/radio) be resynced to a matching August-2026 baseline?
That's a single, deliberate decision with real risk (touches nearly
everything vendor-side at once, and bootloader/radio reflashing is a
categorically higher risk tier — real brick risk — than anything else
patched this session). **Do not attempt a bootloader/radio reflash
speculatively.** If this is ever pursued, it needs the user's explicit,
informed decision with a real matching factory image in hand, not a
patch-and-see attempt.

## Gotchas — build config collisions (found early, mostly ROM-source-tree level)

These recur constantly in this specific tree (`ionutsandroidbuilds`'
device/vendor trees + TheMuppets blobs + GMS + Mist-OS's own layer, none of
which were authored against each other). **Pattern: "already defined by" or
"overriding commands for target" almost always means two sources write to
the same install path.**

**The dominant, most important lesson of the whole session on this topic:
a late `PRODUCT_PACKAGES`/`PRODUCT_COPY_FILES` `$(filter-out ...)` in
`mist_shiba.mk` is unreliable and should not be trusted as a fix** — it
does not work if the colliding/unwanted entry is added by a
*later*-processed makefile (inherit-product ordering means `mist_shiba.mk`
often gets evaluated before the file that actually adds the thing you're
trying to remove). **Confirmed non-working via `get_build_var
PRODUCT_PACKAGES | tr ' ' '\n' | grep <name>` at least 6 separate times
this session** across biometrics virtual HALs, FaceUnlock, and other
packages. The reliable fix is always editing the actual source file
directly and removing the `PRODUCT_PACKAGES +=` line at its origin, not
filtering it out downstream. If you find yourself reaching for a
`filter-out` in `mist_shiba.mk`, stop and go find the real source instead.

**A `PRODUCT_COPY_FILES` collision to the same destination from two
different source files is only a hard build error if the CONTENT differs.**
If both source files are byte-identical (`diff` returns nothing), the build
tolerates the duplicate copy silently — confirmed with the `FontPoppins`
overlay case and with `GoogleCamera_6gb_or_more_ram.xml` appearing
identically in both `vendor/google/camera` and `vendor/google/shiba`'s
proprietary tree this session. Don't assume every duplicate destination
needs a fix — `diff` the two sources first.

1. **Kernel/SoC-tree drift**, already applied upstream in the kernel tree —
   only relevant if rebuilding the kernel from scratch: `MIN`/`MAX` macro
   redefinitions, a `DWC3_LLUCTL` redefinition, a VLA false-positive, and
   `CONFIG_USB_RTL8150` defconfig staleness (see kernel section).

2. **Device-tree vs Mist-OS vendor-tree module-name collisions**:
   `ionutsandroidbuilds`' `device/google/zuma` RRO overlays collide by name
   with Mist-OS's own (`vendor/pixel-style`, `vendor/lineage`). Fixed by
   renaming the device-tree side with a `Shusky` prefix.

3. **`PRODUCT_COPY_FILES` collisions between TheMuppets' real vendor blobs
   and GMS's own Soong `prebuilt_etc` modules** — repeated *fourteen times*
   in `vendor/google/shiba/shiba-vendor.mk` early in this project. Swept
   the whole GMS blob tree in one pass rather than fixing errors one at a
   time — worth doing this kind of sweep immediately whenever a *second*
   instance of the same collision pattern shows up.

4. **Make hazard**: never inline-comment (`# ...`) one line in the middle
   of a backslash-continued list — the `#` eats the rest of the physical
   line including the trailing `\`, breaking the list. Delete the line
   outright instead.

5. **XML comments can never contain a double-hyphen (`--`) anywhere.**
   This bit this session **repeatedly** (at least 4 separate times) when
   writing explanatory comments into sysconfig/vendor XML files — `xmllint`
   (and the real build's own XML validation step) rejects it outright with
   `parser error : Double hyphen within comment`, causing a real build
   failure. **Always run `xmllint <file> >/dev/null` immediately after
   editing any XML comment, before considering the edit done.** Prefer a
   semicolon or just restructuring the sentence over a dash construction.

6. **This tree hardcodes `TARGET_USES_MINI_GAPPS := true`** in both
   `device/google/shusky/mist_shiba.mk` and `mist_husky.mk`. This means
   `vendor/gms/gms_full.mk` is **never inherited for this device, ever** —
   it's safe to edit `gms_full`-only-adjacent shared files (like
   `pixel_experience_2017.xml`, which lives under `vendor/gms/product/
   blobs/` and is shared infrastructure, not gated by the mini/full split
   itself) without worrying about a variant conditional, since only the
   mini path is ever actually built for this device.

7. **Two separate GSI artifact-path-requirement (APR) checkers** each
   report their own offender list on separate passes. Both go into
   `PRODUCT_ARTIFACT_PATH_REQUIREMENT_ALLOWED_LIST` in `mist_shiba.mk` —
   cosmetic GSI-compat lint, functionally inert on a real device.

8. **Partition-size overflow** from custom additions (kernel modules,
   JamesDSP, GMS) pushing past Google's stock 500MB super-partition safety
   margin. Fixed by narrowing (not removing) the margin to 64MB in
   `device/google/shusky/BoardConfigCommon.mk`:
   `BOARD_SUPER_PARTITION_ERROR_LIMIT := $(shell echo $$(($(BOARD_SUPER_PARTITION_SIZE) - 67108864)))`.

## KSU kernel bootloop — what is known (open project, not started)

Facts as of 2026-09-17:
- The KSU+SUSFS kernel (`~/kernel/out/shusky/dist/`) bootlooped on the
  device on every flash; the identical ROM with the stock prebuilt kernel
  boots. So the kernel (or the module/DTB set that ships with it) is the
  cause. No pstore/`console-ramoops` was ever captured, so the actual
  panic/hang reason is unknown.
- **Source-vintage mismatch is the prime suspect.** The stock prebuilt
  (`device/google/shusky-kernels`, banner `g14047afecd8b-ab16012876`) is
  a Google mixed build (official GKI core `Image`, `CONFIG_LTO_NONE`,
  `TRIM_UNUSED_KSYMS`, `MODULE_SIG_ALL`) from an **August 2026** kernel
  drop, matching the June-2026 vendor blobs. The local `~/kernel` tree is
  `engstk/gs` (blu_spark) for `aosp/` at 2026-05-10, but `private/devices/
  google/shusky` and `private/google-modules/soc/gs` are at **"Update kernel
  to ab/13436313" (2025-06-07)** — a year-old device driver + DTB set. The
  dist build compiles all of that from source (`--config=use_source_tree_
  aosp`), so its 330 modules, 4 DTBs and `dtbo.img` are 2025 drivers
  paired with 2026 vendor HALs and firmware. Commit `14047afecd8b` does not
  exist in the local `aosp` history at all. The module sets even differ
  (`iovad-vendor-hooks.ko`, `rtl8150.ko` upstream vs `iovad-best-fit-algo.
  ko`, `pktgen.ko` local).
- Config deltas beyond KSU/SUSFS (from `extract-ikconfig` on the stock
  `Image` vs `dist/.config`): `LTO_CLANG_FULL` (stock: none),
  `UNAME_OVERRIDE`, `TCP_CONG_BBR`, `NET_PKTGEN=m`, no `TRIM_UNUSED_KSYMS`,
  no `MODULE_SIG_ALL`, `quiet` added to `CONFIG_CMDLINE`. Secondary
  suspects; the vintage mismatch dwarfs them.

**User decision 2026-09-17: ship the ROM with the stock kernel; root is
handled separately by flashing engstk's prebuilt blu_spark kernel later.**
Research done for that (so nobody re-does it):
- `engstk/gs` publishes prebuilt releases; **r271 (2026-09-16)** has a
  `gs-susfs` variant (`blu_spark_r271-gs-susfs_6a75ce1.img` = boot.img,
  header v4, kernel `6.1.162+blu-spark`, 420 kernelsu/susfs symbols, and a
  matching AnyKernel3 `.zip` containing just `Image.lz4`). Changelog says
  KernelSU-Next v3.3.0 + SUSFS v2.3.0 built-in, defconfig refreshed from
  Android 17 (CP31.260623.012), Linux 6.1.162, SPL 2026-09. Variants:
  `gs` (stock), `gs-los` (LineageOS-based ROMs), `gs-next`, `gs-susfs`.
  Downloaded copies + sha1 (verified) are in `/tmp/claude-4392/bs/` for
  this session only. Our local `~/kernel` checkout is at `3240d8f` = the
  r268 susfs release commit, so engstk's own build of that same source
  boots for his users — our build method was the difference.
- `ionutsandroidbuilds/kernelsunextzuma` (the device-tree maintainer's
  repo) is NOT a kernel: it's pre-patched `init_boot` images for
  KernelSU-Next **LKM/GKI mode** (v3.1.0 "spoofed", `fastboot flash
  init_boot kernelsu_next_spoofed_310_33024_shiba.img`). That path keeps
  the stock kernel and needs no rebuild, but has no SUSFS. KernelSU-Next
  v3.3.0 (2026-07-03) also ships `android14-6.1_kernelsu.ko` for the same
  LKM approach via its manager app.
- Note our ROM's `boot.img` is kernel-only (modules live in
  `vendor_kernel_boot`/`vendor_dlkm`); a foreign kernel `Image` must be
  KMI-compatible with those modules (android14-6.1 KMI, which blu_spark
  is) — that's why blu_spark ships as an AnyKernel zip that only swaps
  `Image.lz4`.

Recommended approach if a self-built KSU kernel is ever attempted again:
1. Sync a kernel tree at the **same drop the prebuilt came from** (the
   `ab16012876` build ID; AOSP `kernel/manifest` android-gs-shusky
   6.1 branch for Android 17, or whatever ionutsandroidbuilds built their
   prebuilt from — check their kernel repo), not `engstk/gs` + stale
   private/ trees.
2. Add KernelSU-Next + SUSFS on top with **no other config changes**
   (drop blu_spark's LTO/BBR/uname extras for the first attempt).
3. Build the full set (Image + all modules + DTBs + dtbo) from that one
   tree; a kernel can't be tested in isolation on this device because
   `vendor_dlkm`/`vendor_kernel_boot` modules must match it.
4. Before calling it good, capture `/sys/fs/pstore/console-ramoops-0`
   after any failed boot (boot back into the working slot and pull it) —
   that is the only way to turn "it bootloops" into a root cause.

## Gotchas — the kernel saga (KernelSU-Next + SUSFS)

**What went wrong initially:** `device/google/shusky-kernels/` (the
directory `TARGET_KERNEL_DIR` points at, populated by `repo sync`) already
held the *correct, newer* custom kernel. Meanwhile the separately-built
`~/kernel/out/shusky/dist/` held a *stale* build with KernelSU-Next/SUSFS
never actually compiled in. The initial diagnosis got this backwards and
`device/google/shusky-kernels/` was overwritten with the stale build — a
real regression, caught only because of habitually verifying by
decompressing and reading the actual kernel version banner string rather
than trusting file sizes or checksums.

**How to verify which kernel is which, always:**
```bash
out/host/linux-x86/bin/unpack_bootimg --boot_img <boot.img> --out /tmp/check
lz4 -d -f /tmp/check/kernel /tmp/check/kernel.decompressed
strings /tmp/check/kernel.decompressed | grep -i "linux version"
```
A `-dirty` suffix in the version string means it's genuinely a local build
with uncommitted changes — a strong signal it's the custom build, not a
clean official CI build. **Never trust file size/checksum alone** — a
re-signed boot.img changes checksum via `avbtool`'s salt even with
identical kernel content.

**The real root cause:** a full custom defconfig
`aosp/arch/arm64/configs/blu_spark_defconfig` existed in `~/kernel` but was
**never wired into the Bazel build** — `private/devices/google/shusky/
BUILD.bazel`'s `defconfig_fragments` filegroup never referenced it. Every
kernel build silently used a config with no KernelSU/SUSFS at all, even
though the defconfig file existed on disk the whole time.

**The full fix** (all four pieces needed, discovered one compile error at a time):

1. Copy `blu_spark_defconfig` into `private/devices/google/shusky/
   blu_spark_defconfig` (avoids cross-package Bazel visibility issues) and
   add it as the *last* entry in that package's `defconfig_fragments`
   filegroup in `BUILD.bazel`.

2. Strip 5 toolchain-auto-detected lines from the *copied* fragment
   (`CONFIG_CC_VERSION_TEXT`, `CLANG_VERSION`, `AS_VERSION`, `LLD_VERSION`,
   `PAHOLE_VERSION`) — these conflict with this tree's actual toolchain and
   make Kleaf's config-merge validation fail outright. Leave the *original*
   fragment file untouched.

3. `device.bazelrc` defaults to `--use_prebuilt_gki=true` with a pinned,
   stale official build number — the base GKI kernel gets *downloaded*
   rather than built from local source, causing a "KMI or sublevel
   mismatch" against the from-source device kernel. Fixed by building with
   `--config=use_source_tree_aosp` (`--use_prebuilt_gki=false`,
   `--kernel_package=@//aosp`). This surfaced a second bug: a stale `#
   CONFIG_USB_RTL8150 is not set` line in `gki_defconfig` that doesn't
   round-trip through Kleaf's `savedefconfig` validation once the base
   kernel is actually built from source — removed it.

4. `CONFIG_NET_PKTGEN=m` (part of blu_spark's fragment) produces
   `net/core/pktgen.ko`, which Bazel's `kernel_build` rule requires
   explicitly declaring in `module_outs` — added it to shusky's own
   `BUILD.bazel`.

**Verify success with three independent signals, not just a clean exit
code:** (a) the build log prints `-- KernelSU version: 32525` /
`KSU_NEW_DCACHE_FLUSH` during the KernelSU driver's own configure step, (b)
`~/kernel/out/shusky/dist/.config` has `CONFIG_KSU=y` and the full
`CONFIG_KSU_SUSFS_*` block, (c) the resulting kernel's `Linux version`
banner carries a `-dirty` suffix. Note `CONFIG_KSU_SUSFS_
HIDE_KSU_SUSFS_SYMBOLS=y` means a plain `strings`/`nm` search of a
*correctly-built* kernel will ALSO show nothing for ksu/susfs symbols —
that check alone is not reliable proof of absence; verify the Bazel
`defconfig_fragments` wiring and `.config` content instead.

**After any kernel rebuild, the `~/kernel/out/shusky/dist/` →
`device/google/shusky-kernels/` copy step must always be redone** — there
is no automation for this:
```bash
cd ~/mistos/device/google/shusky-kernels
rm -f ./*.ko
cp ~/kernel/out/shusky/dist/*.ko .
for f in boot.img dtbo.img Image Image.gz Image.lz4 \
         init.insmod.husky.cfg init.insmod.ripcurrent.cfg init.insmod.shiba.cfg \
         modules.builtin modules.builtin.modinfo modules.load \
         system_dlkm.modules.blocklist system_dlkm.modules.load \
         vendor_dlkm.modules.blocklist vendor_dlkm.modules.load \
         vendor_kernel_boot.modules.load \
         zuma-a0-foplp.dtb zuma-a0-ipop.dtb zuma-b0-foplp.dtb zuma-b0-ipop.dtb; do
    cp ~/kernel/out/shusky/dist/"$f" .
done
```

## Gotchas — biometrics

### Fingerprint — fixed, simple root cause

`android.hardware.fingerprint.prebuilt.xml` (AOSP's own feature-declaration
XML) was never added to `PRODUCT_PACKAGES` anywhere in this device tree,
so `PackageManager.hasSystemFeature(FEATURE_FINGERPRINT)` was false and
Settings hid fingerprint enrollment entirely. Fixed in
`device/google/shusky/device-shiba.mk`:
```makefile
PRODUCT_PACKAGES += android.hardware.fingerprint.prebuilt.xml
```
**Confirmed working on-device.** The real Goodix HAL/service/firmware were
already correctly present the whole time.

Also cleaned up alongside this (not the actual blocker, but real hygiene):
`build/make/target/product/base_product.mk` and `hardware/google/pixel/
common/pixel-common-device.mk` both unconditionally ship the generic/
emulator "virtual" biometrics HAL modules
(`com.android.hardware.biometrics.fingerprint.virtual`,
`...face.virtual`), meant for CTS/VTS testing, not real hardware. Deleted
the two `PRODUCT_PACKAGES +=` lines directly at their source (a
`filter-out` attempt in `mist_shiba.mk` did not work — see the standing
lesson above).

### Face Unlock — the real root cause (corrects an earlier wrong diagnosis)

**Symptom:** the factory/generic face enrollment flow appeared instead of
a real, working Google Face Unlock experience.

**An earlier draft of this document claimed the fix was two resource
flags in a Mist-OS-authored `packages/apps/Settings/res/values/
mist_config.xml`** (`config_face_enroll_use_traffic_light` and
`config_face_enroll_traffic_light_package`), intended to redirect
`FaceEnrollActivityDirector` to Google's real enroll app. **That edit is
harmless and technically correctly compiled (verified via `aapt2 dump
resources`), but it was never the actual bug** — `FaceEnrollActivityDirector`
was never even being invoked, because of the real root cause below. Left
the resource edit in place (it's correct and might matter for something
else later), but do not treat it as "the fix" going forward.

**The real root cause, found only via the user's own live-device debugging
agent doing a `dumpsys face` investigation — not discoverable from boot
logs or static sepolicy analysis alone:** a **"Sense hijack."** This
Lineage/Evolution-X-derived tree bundles `co.aospa.sense` (Paranoid
Android's "Sense," a Megvii-SDK-based *software* face-unlock
implementation) as a package literally named `FaceUnlock`, plus a static
(non-disableable) RRO called `FaceUnlockOverlay.apk`. By default,
`vendor/lineage/config/mist.mk` unconditionally ships this package and
sets `ro.system_ext.face.sense_service=true` (actually
`PRODUCT_SYSTEM_EXT_PROPERTIES += ro.face.sense_service=true`) for any
64-bit-capable device. When this property is true, the patched
`FaceService` registers Sense's own `SenseProvider` as *the* face
provider — confirmed on-device via `dumpsys face` showing `provider:
SenseProvider` at `sensorId: 1008` (`BIOMETRIC_WEAK`) — and the real
Google/Pixel HAL's `FaceProvider` is never even constructed (0 log lines
post-boot, `getSensorProps()` never called). The static
`FaceUnlockOverlay.apk` *additionally* redirects Settings' own
`config_face_enroll` resource to Sense's own enrollment activity,
hijacking the enrollment UI flow too — which is exactly the "generic
enrollment flow" symptom that was originally observed.

**The actual fix**, in `vendor/lineage/config/mist.mk` — wrap the entire
"Face Unlock" block so it's skipped for our two products:
```makefile
ifeq ($(filter mist_shiba mist_husky,$(TARGET_PRODUCT)),)
ifeq ($(TARGET_SUPPORTS_64_BIT_APPS),true)
PRODUCT_PACKAGES += \
    FaceUnlock
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.face.sense_service=true
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.biometrics.face.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/android.hardware.biometrics.face.xml
endif
endif
```
This is the actual source edit — **not** a late filter-out in
`mist_shiba.mk` (tried first, confirmed via `get_build_var` that it does
NOT actually remove `FaceUnlock`/`ro.face.sense_service`, matching the
standing "late filter-out doesn't work" pattern documented above).
Removing `FaceUnlock` also cascades via its own `required` list in
`packages/apps/FaceUnlock/Android.bp` to drop `FaceUnlockOverlay` and all
`co.aospa.sense` support files automatically (Soong only installs
`required` modules when the requiring module is itself installed).
`FaceEnrollOverlay.apk` (targets the real Google enroll app, unrelated to
Sense) is unaffected and stays.

**CONFIRMED WORKING ON-DEVICE**: `sensorId: 1`, `provider: FaceProvider`
(the real Google AIDL HAL), `Strength: 15` (`BIOMETRIC_STRONG` — was
`255`/`WEAK` before), `co.aospa.sense` gone, both `FaceUnlockOverlay`
copies gone, `ro.face.sense_service` unset. This means `BiometricPrompt`
crypto auth and keystore-bound biometrics now genuinely work.

**Retrospective on why this took so long:** real (but non-fatal) SELinux
denials and a plausible-looking Settings resource flag both looked like
stronger signals early on and were chased first; the actual mechanism (a
hardcoded default in a *different* device's/ROM-lineage's own config file,
active by default unless a downstream product explicitly opts out) required
live `dumpsys face` output to actually see. **General lesson for a future
similar "face/fingerprint shows the wrong/generic UI" bug on a
Lineage/crDroid/Evolution-X-derived tree:** check for a bundled
"Sense"/Megvii-style software face-unlock package and a
`ro.*.face.sense_service`-style property EARLY, before assuming it's a
sepolicy or HAL-registration problem.

## Gotchas — audio (JamesDSP)

**Repo: must be `ionutgherman/vendor_JamesDSP`, branch `aidl`** (path
`vendor/JamesDSP`) — **not** `Fleur-Project/packages_apps_JamesDSP`. The
Fleur fork registers via the *legacy* `libhardware`
`audio_effects.xml`/`EffectsFactoryHalLocal` mechanism, which is dead code
on this device: the real audio HAL
(`android.hardware.audio.service-aidl.aoc`) exclusively uses
`EffectsFactoryHalAidl` and never constructs the legacy factory at all.
Confirmed via `strings` on the real HAL binary showing the literal AIDL
config path `/vendor/etc/audio_effects_config.xml` (a *different* filename
from the legacy `audio_effects.xml`) baked in. **Confirmed working
on-device after switching.**

**A real, device-specific bug found and fixed in this exact repo's own
bundled config, worth re-checking any time this repo gets re-synced to a
newer revision:** `vendor/JamesDSP/proprietary/vendor/etc/
audio_effects_config.xml` (as shipped by the `aidl` branch) is a wholesale,
unedited copy of AOSP's own generic reference template
(`hardware/interfaces/audio/aidl/default/audio_effects_config.xml`) with
only the JamesDSP `<library>`/`<effect>` lines added on top. It does NOT
reflect this specific device's real installed library set:
- `acoustic_echo_canceler`/`noise_suppression`/`automatic_gain_control_v2`
  point at `library="pre_processing" path="libpreprocessingaidl.so"` —
  this library **does not exist** on shiba. The real Tensor/Pixel
  implementation is `libaudiopreprocessing.so` instead.
- `eraser`/`extension_effect` point at `liberaser.so`/`libextensioneffect.so`
  — neither exists on this device **at all**, no software fallback either.

**Fix:** rewrite the `<libraries>`/`<effects>` sections in that exact file
to only reference libraries confirmed present in the actual built
`/vendor/lib64/soundfx/` output. Check what's really there after any build
with:
```bash
find out/target/product/shiba/vendor/lib64/soundfx -iname "*.so"
```
Repoint `pre_processing`'s path to `libaudiopreprocessing.so`, and drop
`eraser`/`extension_effect` entirely (along with every generic
`*sw.so`-suffixed software-fallback library entry from the AOSP template —
none of those exist on this device either). Everything else in the
template (`bundle`→`libbundleaidl.so`, `downmix`, `dynamics_processing`,
`haptic_generator`, `loudness_enhancer`, `reverb`, `visualizer`) maps
correctly and needs no change.

**Also fixed this session — JamesDSP crashes whenever the screen turns
off**, mid-playback, the primary real-world use case:
`ForegroundServiceStartNotAllowedException` in
`RootAudioProcessorService.onCreate()`. Root cause: `james.dsp` ships as a
system app (not privileged) with no background-FGS exemption — not in the
deviceidle allowlist by default. Isolation-tested on-device: a plain
power-save allowlist entry alone is sufficient; no `SYSTEM_ALERT_WINDOW`
grant or priv-app move needed. **Fix:** a small new `prebuilt_etc`
sysconfig module, wired via `vendor/JamesDSP/Android.bp` +
`config.mk`, containing:
```xml
<config>
    <allow-in-power-save package="james.dsp" />
</config>
```
**Confirmed working on-device** — appears as a `system` entry (not `user`)
in `dumpsys deviceidle whitelist`, survives a full `/data` wipe (unlike a
manually-granted user battery exemption, which does not survive a wipe and
only helps that one user, not anyone else running this ROM), 0 crashes
across an extended screen-off idle test.

## Gotchas — Google Camera (added this session, wasn't originally in scope)

The real Google Camera app (`GoogleCamera.apk`) does **not** exist anywhere
in this synced tree by default — only `PixelCameraServices` and the
camera HAL/extensions/connectivity framework jars are present, which are
the backend services, not the actual capture app. The default/fallback
camera app on this build is LineageOS's own `Aperture`
(`vendor/lineage/config/common_mobile_full.mk`), which works fine but
isn't "the real Pixel experience."

**Source used:** `ionutsandroidbuilds/proprietary_vendor_google_camera`,
branch `zuma`, gitlab remote, path `vendor/google/camera` — user-provided,
same trust pattern as Face Unlock/JamesDSP (a specific repo the user
pointed to, not something found by guessing). Self-contained:
`Android.bp` declares `android_app_import { name: "GoogleCamera", ...
overrides: ["Aperture", "Camera2"], ... }` and `camera.mk` adds
`GoogleCamera` to `PRODUCT_PACKAGES` plus copies the baseline profile and a
`GoogleCamera_6gb_or_more_ram.xml` sysconfig file (byte-identical to a
copy already shipped by `vendor/google/shiba`'s own proprietary tree —
this exact duplicate destination is a **known-benign** collision, don't
"fix" it, see the collision-tolerance note above). `device/google/zuma/
common.mk` already has a pre-existing `inherit-product-if-exists` hook for
`vendor/google/camera/camera.mk` — no manual product-mk wiring needed once
the repo is synced to that exact path.

**Confirmed working on-device**: `GoogleCamera.apk` installed, `Aperture`
cleanly overridden/removed via the `overrides:` mechanism (no manual
removal needed, no package collision). The inert leftover
`ApertureOverlayShiba.apk` (a vendor RRO whose target package no longer
exists) was removed from `device/google/shusky/device-shiba.mk` (and the
husky twin from `device-husky.mk`) on 2026-09-17 **in source only** — the
`...-0904` build that's currently flashed still carries it (harmless); it
disappears on the next build.

**Related, checked and found harmless:** `mist_shiba.mk` drops zuma's
`default-permissions.xml` to avoid a destination collision with
`vendor/gms`'s own copy. Diffing the two: the GMS copy already carries
every package from zuma's file (GoogleCamera, camera services, Settings
Intelligence, scone, restore, relationships, ...) except
`com.google.android.apps.setupwizard.searchselector`, which isn't
installed anyway. Nothing was actually lost — don't "restore" it.

## Gotchas — GMS ("mini" repeatedly turned out to have cut load-bearing things)

`vendor/lineage/config/version.mk` correctly selects `vendor/gms/
gms_mini.mk` when `TARGET_USES_MINI_GAPPS := true` (hardcoded for this
device, see collision-gotchas section). `gms_mini.mk` was trimmed down from
a much larger set during this project's early phase (removed Assistant
bloat like `PrebuiltBugle`, Wellbeing, `GoogleFeedback`, live wallpapers,
kids supervision, telemetry daemons, etc. — this part of the trim is
fine and intentional).

**But the trim went too far at least three separate times, each causing a
real, confirmed, user-facing crash or missing feature — check this list
before trimming `gms_mini.mk` further, and re-check it if a future update
re-syncs this file from a different source:**

1. **`Velvet` (Google Search/Assistant, `com.google.android.
   googlequicksearchbox`) is required even in a genuinely minimal GMS
   build.** `NexusLauncherRelease`'s own `MySettingsFragment.
   initPreference()` unconditionally calls
   `OSEInfo.getOverlayPackage().equals(OSEInfo.pkg)` with no null check,
   for the `"search_settings"` preference key. `getOverlayPackage()`
   returns `null` when no search-overlay app is installed at all →
   `NullPointerException`, crashing Pixel Launcher's own Settings screen
   on **every single attempt to open Home Settings**. Confirmed via
   `baksmali`-decompiling the actual built `NexusLauncherRelease.apk` and
   reading the exact bytecode, not guessing. Without Velvet there is
   simply no way to open Home Settings on this launcher at all.

2. **`GoogleRestorePrebuilt-v1007163` (`com.google.android.apps.
   restore`, Pixel's Data Restore Tool) is queried directly by
   SetupWizard during first boot** (a `settingscard` content provider
   query) even when the user isn't doing phone-to-phone migration.
   Without it: `Unknown authority` / `SecurityException` from SetupWizard
   on every first boot.

3. **`WallpaperPickerGoogleRelease` (`com.google.android.apps.
   wallpaper`) is the real Pixel wallpaper app**, and
   `NexusLauncherRelease`'s own `wallpaper_picker_package` string resource
   expects this exact package name. It was removed from `gms_mini.mk`
   during the original trim; the WRONG fix (tried and reverted this
   session) was compensating with AOSP's own `packages/apps/
   WallpaperPicker2` plus a custom redirect overlay — the CORRECT fix is
   just restoring the real app. Once restored, `WallpaperPicker2Overlay`
   in `vendor/pixel-style/config/rro_overlays.mk` (which targets
   `com.google.android.apps.wallpaper`) becomes legitimate again — it was
   previously (also incorrectly) removed on the assumption its target
   didn't exist. `WallpaperPicker2PixelOverlay` stays excluded — it
   targets a *different* package variant (`.pixel` suffix) that this
   exact APK doesn't self-identify as. Both overlays share the same
   self-package name (`com.google.android.wallpaper.picker.overlay`) so
   only one can ever install anyway, meaning this specific ambiguity is
   low-risk even if gotten wrong.

**`FilesPrebuilt` (Files by Google) is deliberately excluded** per
explicit user preference (does not want Google Files specifically). This
has a real side effect worth knowing about: `vendor/gms/product/blobs/etc/
sysconfig/pixel_experience_2017.xml` ships a stock `component-override`
that disables `DocumentsUI`'s own launcher icon
(`com.android.documentsui.LauncherActivity`/`ViewDownloadsActivity`),
under the real-Pixel assumption that Files by Google is present as the
one visible file manager. Since we exclude Files by Google, this override
must be corrected or the app drawer has **no file manager icon at all**
— see the dedicated DocumentsUI section below, since this turned out to
be a much harder problem than editing that one XML file.

**General lesson for this codebase specifically:** when the user asks for
"the real X, not an AOSP substitute" and X is currently missing, **check
whether X already exists somewhere in the currently-synced tree first**
(often true — it's just excluded from `gms_mini.mk` from an earlier trim
pass) before assuming it needs to be sourced externally. This pattern
repeated three times this session (Velvet, Restore, Wallpaper) before
Google Camera turned out to be the one genuine "not present anywhere,
needs external sourcing" case.

## Gotchas — DocumentsUI file-manager icon (three attempts, only the third was correct)

This took three separate attempts across this session, each ruled out by
an actual on-device test with a genuinely fresh (`/data`-wiped) boot — read
the whole sequence before touching this again, since the first two
"obvious" fixes both look plausible and both fail silently.

**Attempt 1 (failed): invert `pixel_experience_2017.xml`'s
`component-override` from `enabled="false"` to `enabled="true"`.** Present
and correctly formed on-device, confirmed via `dumpsys package`. Icon
still didn't appear; the components ended up disabled anyway. A control
test on the SAME file — a different package's override
(`com.android.settings`/`.RegulatoryInfoDisplayActivity`, `enabled="true"`)
— proved the override *mechanism itself* works fine in general. Something
specific to this exact package/component was defeating it.

**Attempt 2 (failed): remove the `component-override` block entirely,**
on the theory that with no override present, PackageManager would fall
back to the app's own manifest-declared default (which has no explicit
`enabled` attribute, i.e. enabled by default). Also failed on a genuinely
fresh `/data`-wiped boot.

**Attempt 3 (the real fix) — found only by decompiling the actual shipped
`DocumentsUIGoogle.apk` manifest, not by guessing further or by
referencing other custom ROMs** (they all ship Files by Google and never
needed to solve this specific combination, so there was no reference
implementation to copy from):
```bash
out/host/linux-x86/bin/aapt2 dump xmltree \
  vendor/gms/system/packages/privileged_apps/DocumentsUIGoogle/DocumentsUIGoogle.apk \
  --file AndroidManifest.xml
```
This reveals a real, functioning `com.android.documentsui.PreBootReceiver`,
registered for `android.intent.action.PRE_BOOT_COMPLETED`. This is genuine
Google code that **actively calls `setComponentEnabledSetting()`** on its
own `LauncherActivity`/`ViewDownloadsActivity` at boot time, entirely
independent of any static sysconfig/component-override XML. The manifest
itself has no explicit `android:enabled` attribute on the alias
(confirmed via the same `aapt2 dump`) — the disable is **100% runtime
code**, not a declarative default. `pixel_experience_2017.xml`'s own
original comment was the tell, in retrospect: *"DocumentsUi PrebootReceiver
does not properly hide the launcher in work profile, so we need to include
this as well"* — meaning the static XML override was only ever a
work-profile-specific supplement to this receiver's primary-user logic,
never a substitute or blocker for it. This is exactly why editing that
override in either direction never touched the real mechanism for the
primary user.

**Fix:** disable `PreBootReceiver` itself (so its disabling code path
never runs at all), combined with explicitly setting
`LauncherActivity`/`ViewDownloadsActivity` to `enabled="true"` as a
belt-and-suspenders measure:
```xml
<component-override package="com.google.android.documentsui" >
    <component class="com.android.documentsui.PreBootReceiver" enabled="false" />
    <component class="com.android.documentsui.LauncherActivity" enabled="true" />
    <component class="com.android.documentsui.ViewDownloadsActivity" enabled="true" />
</component-override>
```
This lives in `vendor/gms/product/blobs/etc/sysconfig/
pixel_experience_2017.xml`. **On-device confirmation was pending as of
this writing** — verify with `cmd package query-activities -a
android.intent.action.MAIN -c android.intent.category.LAUNCHER | grep -c
documentsui` (expect >0) and `dumpsys package com.google.android.
documentsui` (expect an empty `disabledComponents` list) before assuming
this worked; if it somehow still fails, the next thing to check is
whether `PreBootReceiver`'s own `PRE_BOOT_COMPLETED` broadcast only fires
once per app-version-install rather than every boot, which could mean a
dirty flash over an already-"migrated" `/data` needs a full wipe to
re-test cleanly.

**General lesson for a future similar "app's icon/component won't stay
enabled/disabled despite correct static config" bug:** check for an
active, code-driven disabling mechanism (a `PreBootReceiver`-style
component reacting to `PRE_BOOT_COMPLETED`/`BOOT_COMPLETED`) inside the
app's own real manifest via `aapt2 dump xmltree` **before** assuming a
static sysconfig/component-override XML is the actual mechanism — Google's
real shipped APK can differ from what's visible in AOSP's public source
tree for the "same" app name.

## Gotchas — StrongBox VINTF retry loop (fixed, real battery win)

**Symptom:** a permanent retry loop in `init`/`servicemanager` — 337
occurrences of `Could not find 'aidl/android.hardware.security.keymint.
IRemotelyProvisionedComponent/strongbox' for ctl.interface_start` per boot,
~3 attempts every 2 minutes forever, **88% of all init error log lines on
the device**. Each attempt includes a blocking 1-second binder wait
(`ServiceManagerCppClient: Waited one second for ...`) — a real, measurable
wakeup/battery cost, not just log spam.

**Root cause:** `device/google/zuma/vintf/manifest.xml` declared this HAL
instance as available, but the **actual vendor blob's own authoritative
VINTF fragment**
(`vendor/google/shiba/proprietary/vendor/etc/vintf/manifest/
android.hardware.security.keymint-service-v3.citadel.xml`, literally
extracted from Google's real blob per its own header comment) only ever
declared `IKeyMintDevice/strongbox` — never the RKP component. This was a
stale/incorrect declaration unique to **our own** device tree file, not
present in the vendor's own source of truth.

**Investigated before fixing (worth preserving the reasoning, since a
"maybe it's just unregistered and fixable" concern was raised and properly
checked, not dismissed):** does the actual citadel keymint binary have RKP
capability at all? `strings` on both shiba/husky copies of
`android.hardware.security.keymint-service.citadel` shows a real
`RemotelyProvisionedComponentDevice` C++ class constructor compiled in,
and it links `android.hardware.security.rkp-V3-ndk.so` — so the *code*
capability genuinely exists. But the service's own `init.rc` passes zero
command-line arguments (registration logic is entirely internal to the
closed binary's `main()`), and the vendor's own authoritative fragment
explicitly does not declare it. Since a closed binary cannot be forced to
register a service it isn't choosing to register, and the vendor's own
fragment is the most authoritative available signal, the correct decision
was to remove our own erroneous declaration (matching observed reality)
rather than gamble on re-adding it. **This does not restore actual
StrongBox attestation** — it only stops the ROM from falsely claiming the
capability exists in VINTF, which is what caused the infinite retry loop.
If this exact Citadel chip generation genuinely supports RKP and it's
truly just a missing registration call, that would be an upstream/blob-level
fix, not something patchable from this device tree.

Confirmed via `hardware/interfaces/compatibility_matrices/
compatibility_matrix.202604.xml` that the framework matrix lists
`"strongbox"` as an allowed, not mandatory, instance name (most Android
devices have no discrete secure-element chip at all) — removing this
declaration does not violate VINTF compatibility.

**Fix:** remove the stray `<hal>` block from `device/google/zuma/vintf/
manifest.xml`.

**Confirmed working on-device:** 337 → 1 retry occurrence per boot, total
init error lines down 84% (383 → 63). Single biggest wakeup/battery-cost
fix found this session.

## Gotchas — boot patch level / hardware attestation (confirmed unfixable, don't repeat this investigation)

**Symptom:** `ro.boot.boot_patchlevel` stays empty (`''`). RKPD (remote key
provisioning) gets rejected by Google's own server: `"Invalid request
payload: Couldn't parse boot_patch_level \`20000000\` of the format
YYYYMMDD or YYYYMM as a valid date."` (`20000000` = year 2000/month
00/day 00, the KeyMint placeholder sent when the boot image carries no OS
patch level at all).

**Root cause chain, fully confirmed via source before attempting any fix:**
`device/google/zuma/BoardConfig-common.mk` sets `BOARD_PREBUILT_BOOTIMAGE
:= $(wildcard $(TARGET_KERNEL_DIR)/boot.img)` — meaning our `boot.img` is
just `cp`'d from `device/google/shusky-kernels/boot.img` plus an AVB hash
footer added (`build/make/core/Makefile:1419-1444`), and **never** goes
through the standard `INTERNAL_MKBOOTIMG_VERSION_ARGS` stamping
(`--os_version`/`--os_patch_level`) that a normally-Soong-built boot image
gets. The original prebuilt `boot.img` (from the separate kernel build)
had both fields literally `None` in its header, confirmed via
`unpack_bootimg`.

**Fix attempted, and verified correct at every layer this build controls:**
```bash
out/host/linux-x86/bin/unpack_bootimg --boot_img device/google/shusky-kernels/boot.img --out <scratch>
# verify kernel content byte-identical first:
sha256sum <scratch>/kernel device/google/shusky-kernels/Image.lz4
out/host/linux-x86/bin/mkbootimg \
  --header_version 4 --kernel <scratch>/kernel --ramdisk <scratch>/ramdisk --cmdline '' \
  --os_version 17 --os_patch_level 2026-08-01 \
  --output <scratch>/boot_repacked.img
cp <scratch>/boot_repacked.img device/google/shusky-kernels/boot.img
```
Use `PLATFORM_SECURITY_PATCH` (`2026-08-01`), not `BOOT_SECURITY_PATCH`
(`2026-08-05`, a different variable specifically feeding
`VENDOR_SECURITY_PATCH`/vendor_boot).

Verified correct via **every** independently-checkable artifact:
- The raw `mkbootimg` header (`unpack_bootimg` shows `17.0.0`/`2026-08`).
- The AVB footer's rollback index (`avbtool info_image` shows
  `Rollback Index: 1785542400`, which decodes via `date -u -d
  @1785542400` to exactly `2026-08-01 00:00:00 UTC` — matching
  `PLATFORM_SECURITY_PATCH` precisely).
- The actual `boot` **and** `init_boot` partitions extracted straight out
  of the real OTA `payload.bin` (via `ota_extractor`, see the "Verifying a
  build artifact" section above) — not just the loose `out/` directory.
  `init_boot.img` was already correct even before this fix (it's built
  fresh by the standard AOSP pipeline, not sourced from the prebuilt
  kernel repo).

**Despite all of the above being provably correct, the physical device
still reports empty `ro.boot.boot_patchlevel` after flashing.** The
`androidboot.boot_patchlevel` kernel cmdline parameter — which is what
ultimately becomes this `ro.boot.*` property — is constructed by the
**actual bootloader firmware (ABL)** at boot time, and this ROM does not
build, sign, or reflash the bootloader partition; it's Google's real stock
firmware already on the physical device. Confirmed the device's actual
flashed bootloader (`ripcurrent-17.0-15199481`) predates even the vendor
blobs (`CP2A.260605.016`), consistent with the wider version-skew issue
(see dedicated section above). The bootloader is not generally broken —
it writes 55+ other `ro.boot.*` properties correctly — it specifically
never emits this one, consistent with an ABL firmware revision that either
predates this exact attestation mechanism or sources the value from
somewhere this ROM's boot/init_boot images don't control.

**Do not repeat this investigation on a future update** unless the
bootloader itself has genuinely changed (e.g. after a deliberate,
user-approved bootloader resync) — the boot.img/init_boot.img side is
provably correct and does not need re-checking. **Do not attempt to
reflash the bootloader or radio partitions speculatively** — that is a
categorically higher risk tier (real, unrecoverable brick risk without
special tooling) than anything else in this build, and requires the user's
own explicit, deliberate decision with a full matching factory image in
hand.

## Gotchas — Clear Calling (REVIVED 2026-09-17 — the earlier "DCS doesn't exist" claim was WRONG)

**Correction:** the DCS APK **was in the tree the whole time** at
`vendor/gms/system_ext/packages/privileged_apps/DeviceConnectivityServicePrebuilt_26.01.00/`
(module `DeviceConnectivityServicePrebuilt_26.01.00`, `Android.mk`,
`LOCAL_SYSTEM_EXT_MODULE`/`LOCAL_PRIVILEGED_MODULE`). It is listed in
`gms_full.mk` only — the mini GMS choice dropped it (same pattern as Quick
Tap and Velvet). The `PRODUCT_PACKAGES += com.google.android.apps.pixel.dcservice`
line in `system-ext_blobs.mk` is not dangling either: it's the privapp
permission XML module (`system_ext/blobs/etc/permissions/Android.bp`).
Verified against the real factory image `shiba-cp2a.260605.012`
(downloaded to `~/factory/`, images extracted under
`~/factory/shiba-cp2a.260605.012/img/`, ext4 via `debugfs`):
- factory `/system_ext/priv-app/DeviceConnectivityServicePrebuilt_26.01.00/`
  APK = same versionCode 25253 / versionName `25.42.00.821424992…` / same
  signing cert as the tree copy (raw sha differs only by packaging);
- factory `system_ext/etc/permissions/com.google.android.apps.pixel.dcservice.xml`
  and `default-permissions-…dcservice.xml` are byte-identical to ours;
  `privapp-permissions-google-p.xml` grants (INTERACT_ACROSS_USERS,
  MODIFY_AUDIO_ROUTING) identical; hidden-API allowlist entry present in
  both; vendor `persist.vendor.audio.cca.enabled/unsupported=false`
  identical. (The earlier note about missing `CAPTURE_AUDIO_OUTPUT` /
  `CONTROL_INCALL_EXPERIENCE` grants was wrong — Google doesn't grant them
  to DCS either.)
- DCS's own manifest has an `IA_SETTINGS` activity with action
  `com.android.settings.action.CLEAR_CALLING`, so the toggle appears in
  AOSP-based Settings too — **SettingsGoogle is not required**.
- Side finding: that factory image ships bootloader
  `ripcurrent-17.0-15199481` — identical to what's on the phone — so the
  bootloader is NOT older than the blobs; the "version skew" chain in the
  earlier section is wrong on that point (radio/vendor/bootloader all match
  cp2a.260605). The empty `ro.boot.boot_patchlevel` therefore is simply how
  this firmware behaves, not a mismatch.
**Fix:** `DeviceConnectivityServicePrebuilt_26.01.00` added to
`gms_mini.mk`'s system_ext/priv-app list. **CONFIRMED WORKING ON-DEVICE
2026-09-17** (build `...-1253`): toggle present under Settings → Sound &
vibration, and a real 7-minute wideband call logged
`AHal::AudioMetric::AtomWriter: CcaAtom: source: VOICE, status: {
is_ignored: 0, is_active: 1, is_ui_on: 1, band: WB,
duration_cca_enabled_second: 428 }`. **Verification recipe:** place a call
with the toggle on, hang up, then `adb shell "logcat -d | grep -E
'CcaAtom|SaveSuezDataEndCall'"` and read `is_active`/`is_ui_on`/
`duration_cca_enabled_second`. Do NOT use `getprop
persist.vendor.audio.cca.enabled` from adb shell — SELinux denies the read
(`Access denied finding property`) so it always prints empty; same
property-visibility trap described earlier in this file. "CCA Gain
mute/unmute" / "CCA rb underrun" / `AOC: CCA unloaded` lines at call end
are normal teardown chatter.

Original root-cause notes (kept; the "APK missing" conclusion is superseded):

- The audio HAL and kernel driver sides are **both already fully capable**
  — confirmed via `strings` on the real `android.hardware.audio.
  service-aidl.aoc` binary showing a complete Binder API surface
  (`setCcaEnabled`/`getCcaEnabled`/`setCcaUnsupported`/`setCcaVoipCoex`,
  plus `persist.vendor.audio.cca.enabled`/`.unsupported`/
  `.control.from.audiomanager.disabled` and a `vendor.pixel.cca.*`
  property namespace), and via the `audiometrics.c` kernel driver's real
  `AMCS_OP_CCA`/`AMCS_OP_CCA_INCREASE` ioctl interface
  (`private/google-modules/amplifiers/audiometrics/audiometrics.c` in the
  kernel tree). Two of the three `persist.vendor.audio.cca.*` properties
  are already correctly set in `device/google/zuma/vendor.prop`; the third
  (`.control.from.audiomanager.disabled`) and the `vendor.pixel.cca.*`
  namespace are not set anywhere and aren't even labeled in
  `property_contexts`.
- **The actual, fully missing piece is DCS** —
  `com.google.android.apps.pixel.dcservice` (Device Connectivity Service).
  The APK itself does not exist anywhere in the synced vendor tree at all
  — only its permission XMLs do (`default-permissions-com.google.
  android.apps.pixel.dcservice.xml`, a dedicated privapp-permissions file).
  `vendor/gms/system_ext/blobs/system-ext_blobs.mk` has a **dangling**
  `PRODUCT_PACKAGES += com.google.android.apps.pixel.dcservice` line with
  no backing Soong module anywhere — the build silently tolerates the
  unresolvable package name rather than hard-failing.
- Two real permission gaps found in the existing (installed but useless
  without the APK) permission files: `CAPTURE_AUDIO_OUTPUT` and
  `CONTROL_INCALL_EXPERIENCE` are not granted to `dcservice` anywhere
  (present in the file, just attached to other packages). Google's real
  commit adding a `READ_PHONE_STATE` default-permission exception for
  logging also isn't present in this blob revision.
- No open-source implementation of DCS exists anywhere to copy from. Would
  need extraction from a real stock Pixel 8 factory image — and the
  correct extraction target is `CP2A.260605.016` (the real vendor blob
  vintage, confirmed via `ro.vendor.build.id`), **not**
  `CP2A.260805.005` (the platform's spoofed `ro.build.fingerprint` — do
  not use the fingerprint as an extraction-target signal, it's
  intentionally spoofed and ~2 months newer than the actual blob vintage).
- Likely also needs a real Settings/dialer UI host for the actual toggle,
  tying this to the deferred Pixel Framework question (see below) — even
  if DCS itself were extracted and wired in, there may be no UI surface to
  enable/see it without a real Google Settings app.

## Pixel Framework port — INVESTIGATED AND PARKED (2026-09-17, ~2.5 h, 3 agents)

**Outcome:** not integrated. The clone was **moved out of the tree to
`~/pixel-framework_rising_sixteen`** (with one local edit kept:
`SystemUIGoogle/proto/Android.bp` emptied because it duplicated
`smartspace-proto-java`/`smartspace-proto-lite-java` from
`frameworks/base/packages/SystemUI/proto/Android.bp` and broke whole-tree
Soong analysis). **Never leave it inside `~/mistos/vendor/` unless you also
add `filegroup { name: "Settings_manifest", srcs: ["AndroidManifest.xml"] }`
to `packages/apps/Settings/Android.bp`** — otherwise Soong fails tree-wide
("SettingsGoogle-core depends on undefined module Settings_manifest") and
NO module builds, not just the Google ones.

Targeted-compile findings (build agent):
- `SettingsGoogle`: javac/kotlinc of `SettingsGoogle-core` + `SettingsGoogle`
  **compile clean** once `Settings_manifest` exists; the next blocker is the
  manifest merge (`<application android:name>` conflict → needs
  `tools:replace="android:name"` on SettingsGoogle's `<application>`,
  `AndroidManifest.xml:171`). aapt2/R8/dex stages never reached. The jar's
  API-skew symbols (below) would surface at R8/runtime, not javac.
- `SystemUIGoogle`: 42 javac/kotlinc errors, all in
  `com.google.android.systemui.smartspace.*` against Mist's
  `BcSmartspaceDataPlugin`/`LogBufferFactory` APIs — confirms it's a stale
  duplicate of what Mist's SystemUI already has.
- Logs: `/tmp/claude-4392/pf/build/BUILDLOG.md` (session scratch).

- Base was cloned (plain `git clone`, never in the manifest) as
  `vendor/pixel-framework` = RisingOS-Revived/android_vendor_pixel-framework
  branch `sixteen` (HEAD 2bf5674, "Adapt SystemUIGoogle/SettingsGoogle for
  16-QPR0"). Contents: `SystemUIGoogle` (61 Google source files stacked on
  our `SystemUI-core`, overrides `SystemUI`), `SettingsGoogle` (prebuilt
  `SettingsGoogle-lib.jar` + 11 sources on our `Settings-core`, overrides
  `Settings`), `google_battery`/`fingerprint_ext` AIDL, `proto`, `config.mk`
  (just `PRODUCT_PACKAGES += SystemUIGoogle SettingsGoogle`).
- Verified 2026-09-17: no Android-17 port exists anywhere on GitHub.
- RisingOS needed hook commits in their frameworks/base + Settings
  (`sixteen` branches) — e.g. "Integrate Pixel framework hooks and
  wrappers" e63eec8, "Add required priv-app permissions for SystemUIGoogle"
  2cf8a69, "HierarchySnapshotter (2/2)" 50ebe39, "Stub PluginProtector"
  b5f5428, "EnhancedEstimates: Device Health Services" 3cd5ff7,
  "SettingsGoogle: ContextualScreenTimeout" 0ed3df4. Analysis reports land
  in `/tmp/claude-4392/pf/{sysui,settings}/REPORT.md`, build iteration log
  in `/tmp/claude-4392/pf/build/BUILDLOG.md` (session-scratch; copy
  anything durable here).
- Method: targeted `m SettingsGoogle` / `m SystemUIGoogle` builds (one at a
  time), fix inside vendor/pixel-framework first, apply framework/Settings
  hooks centrally, re-build; only then add `config.mk` to `mist_shiba.mk`
  and do a full build. Treat SystemUIGoogle as high-risk (a crash-looping
  SystemUI makes the phone unusable) — the first flash of it is a test.
- **`vendor/pixel-framework` is NOT wired into the product yet.** The
  published `...-1036` build does not contain it.

**SystemUIGoogle analysis result (2026-09-17, decisive — don't redo):**
- RisingOS `sixteen`'s "Adapt SystemUIGoogle for 16-QPR0" commit (9e349ee)
  deleted **27,126 lines**: `columbus`, `ambientmusic` (Now Playing on
  lockscreen), `assist`, `dreamliner`, `power`, `reversecharging`, `qs`,
  `statusbar`, `theme`, `elmyra`, `controls`, `screenshot`, `gesture`,
  `input`, plus `GoogleServices`/`SystemUIGoogleInitializer`. What's left
  is 59 Smartspace files + 2 Dagger glue files + 48 res files + back-gesture
  tflite assets, and four Google jars (`nga-lib`, `matchmaker`,
  `touchcontext`, `googlebattery-lib`) that **no remaining source
  references** (R8 would strip them).
- Mist's own `frameworks/base/packages/SystemUI` **already contains the
  same `com.google.android.systemui.smartspace.*` package (52 files) and
  wires it in `SystemUIModule.java`** (`BcSmartspaceDataProvider`,
  `SmartspaceGoogleModule`). pixel-framework's copy differs in 46 files and
  adds 10 (an AppSearch "next alarm" card: `AlarmAppSearchController`,
  `NextClockAlarmController*`). Static-linking `SystemUIGoogle-core` on top
  of `SystemUI-core` therefore produces **duplicate classes** — RisingOS's
  frameworks_base has only 1 file under `packages/SystemUI/src/com/google`,
  so their tree never had the conflict. Net value of `sixteen`
  SystemUIGoogle over Mist's SystemUI ≈ a newer smartspace + alarm card, at
  the cost of replacing the whole shell. **Verdict: not worth it; skipped.**
- Everything the user actually wants from "Pixel SystemUI" lives in the
  **`fifteen`** branch (Android 15, last touched 2025-03-06; crDroid `15.0`
  is the same set). Porting that to Android 17's SystemUI (Compose scenes,
  keyguard blueprints, new QS) is a multi-week expert project; RisingOS
  didn't do it for 16, Evolution-X dropped SystemUIGoogle entirely. If ever
  attempted: start from `fifteen`, feature-by-feature (e.g. `reversecharging`
  QS tile, `ambientmusic`), as additions to Mist's SystemUI — not by
  overriding `SystemUI` wholesale.
- Hook-commit facts for the record (from a partial clone of RisingOS
  frameworks_base `sixteen` at `/tmp/claude-4392/pf/rising_fb`, patches in
  `/tmp/claude-4392/pf/sysui/patches/`): priv-app permission commits
  (2cf8a69, 17ec508, e61ef88) are already satisfied by Mist's
  `data/etc/com.android.systemui.xml`; e63eec8 "Integrate Pixel framework
  hooks" is obsolete (Mist uses the newer `PhoneSystemUIAppComponentFactory`
  / `ReferenceGlobalRootComponent` mechanism, a Google variant would be a
  new `GoogleGlobalRootComponent`, not that patch); the SHAs 50ebe39,
  b5f5428, 82cb913 from the commit search were phantoms (tree objects);
  `PluginProtector` and `EnhancedEstimates` already exist in Mist. One
  genuinely useful, standalone item: a798cbc "Do not crash SystemUI if
  smartspace cannot be built" — Mist's `LockscreenSmartspaceController.kt`
  still throws `RuntimeException("Cannot build view when not enabled")` at
  three sites (~lines 366/386/406); hand-port "return null" there if a
  smartspace-related SystemUI crash ever shows up.

**SettingsGoogle analysis result (2026-09-17):** buildable in principle —
every module in `SettingsGoogle/Android.bp` resolves in Mist's tree
(`Settings-core`, `SpaLib`, `SettingsLib-search-defaults`, datastore/room
libs, `android.hidl.base-V1.0-java` and `android.frameworks.stats-V1-java`
are auto-generated, `vendor-pixelatoms-java` comes from
`vendor/pixel-framework/proto`). But: (1) the prebuilt
`SettingsGoogle-lib.jar` (1101 classes) targets an older
`com.android.settings` API than Mist's — it wants
`accessibility.AccessibilityMetricsFeatureProvider` (Mist has the renamed
`AccessibilityPageIdFeatureProvider`) and
`biometrics.fingerprint.feature.SfpsRestToUnlockFeature` (RisingOS Settings
a9913cb), so a compat shim/manual port is needed; (2) 8 of the 9 RisingOS
hook commits do NOT apply to Mist (Settings: ec6dcb5 face auto-rotate,
01575ba advanced VPN, ffb6e7e ContextualScreenTimeout [the SHA 0ed3df4
doesn't exist], a9913cb SfpsRestToUnlock; frameworks/base: 3cd5ff7
EnhancedEstimates DHS, 5c26426 BatteryManager intent, 376d014
BatteryService capacity API) — only c64f7f7 "localepicker" 3-way-applies;
(3) `SettingsGoogle/res` collides on **116 non-values resource files**
with Mist's `packages/apps/Settings/res`, all recently re-themed by Mist
(`c29acb1`), and SettingsGoogle's copies would silently win; (4) one
source fix: `BatterySaverModePreferenceController.java` imports
`com.android.internal.util.android.Utils` → Mist's is
`com.android.internal.util.mist.Utils` (same `isPackageInstalled`
signature). Patches + symbol lists were saved under
`/tmp/claude-4392/pf/settings/` (session scratch). **Verdict: real work
(days), and it delivers none of the user's actual goals** — see next item.

**What the user actually wanted from "Pixel Framework" (stated
2026-09-17): Now Playing on the lock screen, and Clear Calling.** Neither
needs Pixel Framework: Clear Calling is blocked on the missing DCS app
regardless (SettingsGoogle only has the toggle UI), and lockscreen Now
Playing is a **Mist-native feature** that was simply never enabled:
- Mist's SystemUI has its own implementation
  (`packages/SystemUI/src/com/android/systemui/nowplaying/`,
  `ax/AxPlatformObservers.kt` registers the
  `com.google.android.ambientindication.action.AMBIENT_INDICATION_SHOW/
  EXPAND/HIDE` receiver guarded by the
  `com.google.android.ambientindication.permission.AMBIENT_INDICATION`
  permission that SystemUI's own manifest declares as
  `signature|privileged`).
- Gate: `Settings.System.nowplaying_enabled`, **default 0**
  (`NowPlayingSettingsRepository.kt`). UI toggle: **Mistify → Lock screen
  → Now Playing** (`packages/apps/Mistify/res/xml/nowplaying_settings.xml`).
- Sender is **Android System Intelligence** (`com.google.android.as`,
  `product/priv-app/DevicePersonalizationAiAiPrebuiltPixel2023`), which
  requests that permission (`uses-permission` confirmed via aapt2; the
  new `NowPlayingPrebuilt` app `com.google.android.apps.pixel.nowplaying`
  never references ambientindication — it's only the history UI). No
  privapp-permissions file in the image lists `AMBIENT_INDICATION` for
  any package (`ro.control_privapp_permissions=enforce`). Whether that
  matters depends on whether the allowlist is enforced for
  SystemUI-declared (non-`android`) permissions — verify on-device with
  `dumpsys package com.google.android.as | grep -A1 ambientindication`
  (`granted=true/false`). If false: add
  `<permission name="com.google.android.ambientindication.permission.AMBIENT_INDICATION"/>`
  to the `com.google.android.as` block in
  `vendor/gms/product/blobs/etc/permissions/privapp-permissions-google-p.xml`
  and rebuild.

## Now Playing on the lock screen — ported Pixel "ambient indication" (2026-09-17)

**Root cause (device agent + source):** Mist's "Now Playing" lockscreen
feature (`SystemUI/nowplaying/`, Mistify → Lock screen → Now Playing) is a
*local media-session* widget (title/artist/lyrics of whatever app is
playing) — unrelated to Google's ambient song recognition. ASI
(`com.google.android.as`) recognizes songs fine, holds the
`AMBIENT_INDICATION` permission, and its `AMBIENT_INDICATION_SHOW`
broadcast is delivered to SystemUI (verified via `dumpsys activity
broadcasts`) — but the only receiver, `ax/AxPlatformObservers.kt`,
forwards it to `AxPlatformClient.KEY_NOW_PLAYING`, which **nothing in the
tree consumes**. AOSP's hook points exist (`layout/ambient_indication.xml`
is an empty `<merge/>` stub included by `keyguard_bottom_area.xml`;
`CentralSurfacesImpl`/`DozeServiceHost` already look up
`R.id.ambient_indication_container`), so the fix is porting Pixel's small
`ambientmusic` implementation into Mist's SystemUI.

**What was added (frameworks/base/packages/SystemUI, from
`~/pixel-framework_rising_sixteen` branch `fifteen`, FETCH_HEAD):**
- `src/com/google/android/systemui/ambientmusic/AmbientIndicationContainer.kt`
  (adapted: `NotificationMediaManager` is now in `com.android.systemui.media`;
  `DelayedWakeLock(bgHandler, context, logger, tag)` lost its main-handler
  arg; `ShadeViewController.setAmbientIndicationTop()` no longer exists →
  call dropped; all view access null-safe).
- `src/com/google/android/systemui/ambientmusic/AmbientIndicationService.java`
  (as upstream, receiver for SHOW/HIDE with the permission guard, TTL alarm,
  user-switch handling; typed `getParcelableExtra`).
- `src/com/android/systemui/ambientmusic/AmbientIndicationAreaSection.kt`
  (new, Mist-side): a `KeyguardSection` bound to AOSP's optional
  `KEYGUARD_AMBIENT_INDICATION_AREA_SECTION` slot (`@Binds @Named` added in
  `keyguard/ui/view/layout/sections/KeyguardSectionsModule.kt`, consumed by
  `DefaultKeyguardBlueprint`/`SplitShadeKeyguardBlueprint`). It inflates
  `layout/ambient_indication` into `KeyguardRootView`, constrains it
  BOTTOM→TOP of `keyguard_indication_area` and START/END→parent, calls
  `initializeView(...)`, creates the `AmbientIndicationService`, and stops
  it in `removeViews` (blueprint rebuilds). Also reports text visibility to
  `KeyguardInteractor.setAmbientIndicationVisible()` (AOSP uses it to shrink
  the notification stack).
  **First attempt (build `...-1253`) used a CoreStartable + the legacy
  `keyguard_bottom_area.xml` include instead and rendered nothing:** the
  device agent's view dump showed `KeyguardBottomAreaView` is inflated but
  permanently GONE on Android 17 (superseded by `KeyguardRootView`), so the
  container was VISIBLE at 0×0 inside a GONE parent — while the service
  logged "Showing ambient indication." happily. Trap noted by the agent:
  `R.id.keyguard_indication_area` exists in BOTH trees (dead LinearLayout in
  the bottom area, live `KeyguardIndicationArea` in the root view), so
  naive `findViewById` from the window root can resolve the dead one. The
  include was removed from `keyguard_bottom_area.xml` (comment left in
  place) so exactly one container exists.
  **CONFIRMED WORKING ON-DEVICE on build `...-1358`** (user: "the song
  shows on the lock screen"). One cosmetic follow-up: the pill sat at the
  left edge — Google's `ambient_indication_inner.xml` is a ConstraintLayout
  whose centering only comes from a runtime-applied ConstraintSet, and the
  outer container had asymmetric 100dp/41dp margins from the old
  FrameLayout placement. Fixed after 1358 by making the inner root a
  FrameLayout with `layout_gravity="center_horizontal|bottom"`, symmetric
  24dp margins, and deleting the `res/xml/ambient_indication_inner_*.xml`
  ConstraintSets + the runtime apply code.
- `res/layout/ambient_indication.xml` (stub → real container),
  `res/layout/ambient_indication_inner.xml`,
  `res/xml/ambient_indication_inner_{downwards,upwards}.xml`,
  `res/values/dimens_ambient_indication.xml` (icon sizes + dock dimens),
  7 drawables (`ic_music_search/not_found`, `ic_cloud_off`, `ic_favorite*`,
  `ic_error`), 69 `res/anim/audioanim_animation*.xml` frames (the animated
  music-note icon). `TextAppearance.Keyguard.BottomArea` already exists in
  `res-keyguard`. SystemUI's manifest already declared/used the permission.
- Verify on-device: `logcat | grep -E "AmbientIndication"` should show
  `AmbientIndicationService started` at boot and `Showing ambient
  indication.` when ASI recognizes a song; song text appears above the
  bottom of the lock screen / on AOD. Mist's own "Now Playing" toggle in
  Mistify is unrelated to this and can stay off.

## Deliberately deferred — Pixel Framework (real SystemUI/Settings source)

The user asked specifically for the *real* Google Settings/SystemUI
experience (Columbus gestures, lock-screen ambient/Now-Playing indication,
Pixel's real battery UI, Quick Tap, etc.) rather than what this build
currently has: AOSP's own Settings.apk/SystemUI.apk with RRO theming on
top (`PixelSettingsGoogle`/`PixelSystemUIGoogle` overlays). **RRO overlays
can only reskin resources — they cannot add new Java behavior/services —
so none of the above is achievable via overlay alone.** The real mechanism
is a community-maintained *source-level fork* of Google's actual
Settings/SystemUI Java code, hand-adapted to each new Android version.

Three candidate repos were checked (all named `vendor_pixel-framework` or
similar):

| Org | Branch | Last push | SettingsGoogle | SystemUIGoogle |
|---|---|---|---|---|
| `Project-Mist-OS/vendor_pixel-framework` | `15` | 2025-01-31 | Yes (A15 QPR1) | Yes (A15 QPR1) |
| `Evolution-X/vendor_pixel-framework` | `bka` (Android 16) | 2025-11-17 | Yes, adapted for 16-QPR0 | **Dropped** ("[TMP] Drop SystemUIGoogle for now") |
| `RisingOS-Revived/android_vendor_pixel-framework` | `sixteen` (Android 16) | 2025-11-13 | Yes, adapted for 16-QPR0 | **Yes, kept and adapted for 16-QPR0** |

**`RisingOS-Revived/android_vendor_pixel-framework` branch `sixteen` is
the clear best candidate if this is ever attempted** — the only one of the
three still shipping both apps together, both freshly adapted for Android
16 QPR0 just days before Evolution-X gave up on `SystemUIGoogle` entirely.
Its `config.mk` is a trivial two-line `PRODUCT_PACKAGES += SystemUIGoogle
SettingsGoogle`. The version gap (16→our 17) is the same order of
magnitude as the successful Face Unlock port (16.0→17), not the two-version
gap that rules out the Project-Mist-OS repo. **Do not default to
`Project-Mist-OS`'s own namesake repo just because the project shares a
name** — it's the most abandoned, oldest, and least complete of the three.

**Deliberately not attempted this session**, because a full SystemUI
replacement carries a categorically different risk than anything else
patched: SystemUI crash-looping can make the entire phone UI unusable
(not "one broken feature"), unlike a standalone app failing. If this is
picked up in a future session, start from RisingOS-Revived's current
branch (check again — branch names/status may have moved on), budget for
a real porting effort (not a quick patch), and treat it as a genuinely
separate, higher-risk project phase rather than folding it into routine
bugfix work.

## Other real fixes this session, for completeness

- `vendor/google/faceunlock/config.mk`: uncommented `BOARD_SEPOLICY_DIRS
  += vendor/google/faceunlock/sepolicy` (was present but disabled).
- Deleted `vendor/google/faceunlock/sepolicy/service.te` (duplicate
  `hal_face_debug_service` type declaration, sepolicy compile conflict
  with zuma's own declaration).
- Added missing `type hal_exo_camera_injection_hwservice,
  hwservice_manager_type;` to `vendor/google/faceunlock/sepolicy/
  hal_exo_camera_injection.te` (a genuine upstream oversight in that
  third-party repo).
- `device/google/zuma/sepolicy/vendor/hal_camera_default.te`: added
  `allow hal_camera_default vendor_camera_data_file:dir create;` — fixes
  a real 4x-per-boot denial (creating a directory literally named
  `video_bokeh_node`; the name is misleading, it's a plain directory
  `mkdir`, not a device node). Scoped to exactly the single missing
  permission the raw `avc:` line requested (AOSP's `rw_dir_perms` macro
  does not include bare `create` on a directory, despite sounding
  comprehensive) — if further permissions (`add_name`/`write`/`search`)
  surface on this same path after this lands, that's an expected
  follow-on (SELinux surfaces one missing permission at a time), not a
  sign this fix was wrong. **Confirmed clean (0 denials) on-device.**
- `device/lineage/sepolicy/common/private/toolbox.te` (this tree's
  established, already-wired extension point for platform/private-side
  domains like `toolbox` — do NOT edit `system/sepolicy/private/
  toolbox.te` directly, use this file instead, following the same
  `device/lineage/sepolicy/common/private/<domain>.te` pattern for any
  similar future need): added `allow toolbox adb_data_file:dir search;` —
  fixes a real functional bug where this ROM's own one-time `/data/adb/*`
  root-hiding-config cleanup script (`system/core/rootdir/init.rc`, gated
  by `persist.sys.mist.spoof.migrated`) was silently failing to actually
  delete anything (`rm -rf` couldn't even traverse into `/data/adb`).
  **Confirmed clean on-device.** Note for anyone using Tricky Store/Play
  Integrity Fix as KernelSU modules: this cleanup deletes
  `/data/adb/tricky_store`, `/data/adb/playintegrityfix`,
  `/data/adb/gameprops`, `/data/adb/.custom_rom_hide_allowlist`, but only
  **once** per fresh `/data`, and only before those paths would exist on
  a truly fresh flash — safe as long as those tools are configured
  *after*, not before, first boot of a fresh flash (the natural order of
  operations anyway).
- `device/google/zuma/sepolicy/vendor/gxp_logging.te`: added `dontaudit
  gxp_logging traced_producer_socket:sock_file write;` — silences a
  benign perfetto-tracing-connection-attempt denial, reusing the exact
  same established pattern already present for `hal_camera_default` in
  this same tree (don't invent a new fix shape for this exact symptom on
  a different domain — reuse `dontaudit ... traced_producer_socket`).
  **Confirmed clean on-device.**
- Removed a dead 5-line `service abox /vendor/bin/main_abox ...` init.rc
  stanza from both shiba and husky's `init.zuma.rc` — leftover reference
  to Exynos audio-box hardware; this Tensor-based device uses AoC for
  audio, and the referenced service binary was never even present, so
  this was pure dead config.
- `vendor/extras/config.mk`: removed a redundant `FontPoppinsSourceOverlay`
  `PRODUCT_PACKAGES` entry, keeping only `ClockFontPoppinsSourceOverlay`
  (byte-identical manifests/self-package names; avoids relying on an
  unpredictable install-order tie-break for a duplicate).
- **`device/google/shusky/sepolicy/vendor/gpuflag.te` + a `file_contexts`
  line** (new, untracked): TheMuppets' blobs ship `/vendor/bin/gpuflag`
  with a `gpuflag.rc` (`exec_background u:r:gpuflag:s0`), but no
  `gpuflag` domain existed anywhere in the device tree, so init's
  `setexeccon` failed with EINVAL every boot and GPU feature flags never
  applied. A minimal domain (`type gpuflag, domain; ... init_daemon_domain
  (gpuflag)`) was added and compiles into `vendor_sepolicy.cil`.
  **Verified on-device 2026-09-17 and CLOSED:** the service now starts
  cleanly and exits 1 after 36 ms with zero avc denials. That exit is the
  binary's own "unsupported device" path — `strings` shows its only sysfs
  target is `/sys/devices/genpd:0:34f00000.gpu0/power/autosuspend_delay_ms`,
  which does not exist on shiba (`ls` confirms; zuma's Mali is at
  `1f000000`, and `34f00000` appears nowhere in the zuma kernel sources),
  and the binary is byte-identical in the husky blobs. It's a shared
  gs-family tool for a newer SoC; exit 1 on zuma is stock behavior. The
  domain stays (it removes a per-boot `setexeccon` error); don't add
  sysfs rules or genfs labels for it — a `sysfs_gpu` rule + genfscon was
  tried and reverted the same day once the node turned out not to exist.
- `device/google/shusky/sepolicy/vendor/trusty_apploader_faceauth.te`,
  `hal_face_default_extra.te`, `audioserver_jamesdsp.te` (new, untracked):
  face-auth TA loading from the vendor APEX, a `metadata_file` dir read
  for the face HAL, and JamesDSP's unlabeled-file/execmem needs. All
  three were part of getting Face Unlock/JamesDSP working; the
  `hal_face_default` → `default_prop` read denial mentioned in
  `hal_face_default_extra.te` is the known-unfixable neverallow class
  (see the benign list below).
- **`DeviceIntelligenceNetworkPrebuiltAstrea` duplicate-module fix:**
  both `vendor/gms` and TheMuppets' `vendor/google/shiba` define a module
  with this name; kati registers every `Android.mk` it finds regardless
  of `PRODUCT_PACKAGES`, so the GMS copy's directory was renamed to
  `...Astrea.disabled` (`Android.mk` → `Android.mk.disabled`). The
  TheMuppets copy is what ships (it IS installed — that's intended, it's
  the real device-specific one). A stale comment in `mist_shiba.mk`
  pointed at a `device_patches/...md` that never existed; corrected
  2026-09-17.

## Confirmed genuinely unfixable or genuinely benign — don't re-investigate these

- **`telephony.ril.modem_bin_status` property_contexts** — this property
  (set by the real vendor `cbd.rc` blob via `setprop
  telephony.ril.modem_bin_status ${vendor.cbd.modem_bin_status}`) is
  **not** vendor-namespaced (doesn't start with `vendor.`/`persist.
  vendor.` etc.), and Android's VTS-enforced `check_prop_prefix` build-time
  check **hard-rejects** any vendor `property_contexts` entry for a
  non-vendor-prefixed property, regardless of what type it's given —
  confirmed via a real build failure attempting exactly this. Reverted;
  documented as a permanently-accepted non-fatal denial. The only real
  fixes (`BUILD_BROKEN_VENDOR_PROPERTY_NAMESPACE := true`, too broad; or
  patching `cbd.rc` to target a different, vendor-prefixed property name,
  risky since other unknown closed-source components may depend on the
  exact literal name) were both judged not worth the risk for a low-impact
  denial (it just tracks which of two modem firmware binary variants is
  active).
- **`mediacodeclist_generator` → `vendor_default_prop`** — hits the same
  hard AOSP neverallow class as the face-unlock `default_prop` case
  (a `coredomain` reading a `*_default_prop` catch-all type is blocked
  platform-wide by design). Genuinely unfixable without weakening a hard
  security rule. Accepted.
- **`hardware_info_app` → `default_prop`** (4x/boot, `com.google.android.
  hardwareinfo`) — an app-domain (not coredomain) case, structurally
  different from the above, but the exact property name can't be
  extracted from a raw `avc:` read-denial line (see the property-visibility
  methodology section) — would need decompiling that specific APK's own
  dex to find candidate keys. Low priority under the battery-first
  framing (no repeating loop, no measurable cost); not worth chasing
  unless it becomes relevant again.
- **`android.xr` aconfig `ERROR_PACKAGE_NOT_FOUND`** — the
  `android.xr.flags-aconfig` Soong module IS correctly declared and wired
  in `frameworks/base/AconfigFlags.bp`. Not a build gap; expected/benign
  on non-XR hardware like a phone.
- **`boost_adpf_prio` write failure** (`Unable to write to file
  '/proc/vendor_sched/boost_adpf_prio': ... Invalid argument`) — this is
  EINVAL, not ENOENT/EACCES, meaning the proc node exists and opens fine;
  the kernel rejects the specific *value* (`-1`, a "no override" sentinel
  written because `persist.device_config.vendor_system_native_boot.
  boost_adpf_prio` is genuinely unset). Very likely stock/expected
  behavior on real hardware too. **Do not touch init ordering for this.**
- **`WiredAccessoryManager` probing a nonexistent Qualcomm sysfs path**
  (`/sys/devices/platform/soc/soc:qcom,msm-ext-disp/...`, 8x/boot,
  confirmed genuinely absent, not a permission denial) — the relevant
  code (`NAME_DP_AUDIO` in `frameworks/base/services/core/java/com/
  android/server/WiredAccessoryManager.java`) is deeply embedded across
  18+ call sites in a core, actively-used AOSP framework class, not a
  small guardable device-specific patch. Purely cosmetic; not worth the
  risk of patching core framework logic for a log line.
- **`CompatConfig`/`AppCompatOverridesService` main-thread stall** (~1.3s,
  observed twice in 22 minutes, `W CompatConfig: Trying to remove
  overrides for unknown Change ID ...` × ~3,640 lines per burst) —
  confirmed via source that this is **unmodified AOSP platform code**
  (`frameworks/base/services/core/java/com/android/server/compat/
  overrides/AppCompatOverridesService.java`) deliberately registering its
  `DeviceConfig` listener on `mContext.getMainExecutor()` — an AOSP
  architectural choice present on any device with this framework version,
  not something this ROM introduced. The actual trigger is a live Google
  Phenotype/`DeviceConfig` server push (namespace `app_compat_overrides`)
  referencing 4 specific numeric Change IDs that don't exist in this
  platform's compiled compat config — most likely Google-internal-only
  framework compat changes that simply don't exist in any AOSP-derived
  custom ROM, not something restorable from our source tree. Not fixable
  from our side; if pursued further, the right action is reporting the 4
  Change IDs upstream to AOSP, not a ROM-side patch.

- **`Gallery2` and `Glimpse` both installed** — not a duplicate icon:
  Glimpse's `overrides:` list only names `Gallery`/`Gallery3D`/
  `GalleryNew3D`, so AOSP's `Gallery2` (from `handheld_product.mk`) still
  ships, but `aapt2 dump badging` confirms it has **no launchable
  activity** — it only shows up as an "open with" chooser option. Cosmetic;
  ignore.
- **`com.google.android.apps.pixel.dcservice` permission XMLs** still
  install without the APK (dangling `PRODUCT_PACKAGES` line in
  `vendor/gms/system_ext/blobs/system-ext_blobs.mk`). Harmless
  (PermissionController ignores grants for absent packages); left alone
  since Clear Calling is dropped.
- **`ro.build.display.id=CP2A.260605.016 test-keys`** while
  `ro.build.description`/fingerprint say `CP2A.260805.005 release-keys` —
  the display ID comes from the vendor-blob build ID, the fingerprint is
  the deliberate spoof in `mist_shiba.mk`. Cosmetic (Settings > About
  shows the June ID). Don't "fix" the fingerprint side — it's spoofed on
  purpose for Play Integrity.

## Mist device-flag / About-phone pass (2026-09-17, in source, NOT yet built)

Done after the `...-0904` build was flashed; needs a rebuild to take effect.

- **About phone hardware card was entirely "Unknown".** Mist's Settings
  (`packages/apps/Settings/src/com/mist/utils/AboutPhoneData.java`) reads
  `ro.mist.soc/battery/display/camera/front/platform/screen` and
  `HyperPreference.java` reads `ro.mist.device.name`; nothing set them.
  Added `device/google/shusky/shiba/mist_about.prop` (Pixel 8 values) and
  `TARGET_PRODUCT_PROP += $(DEVICE_PATH)/$(DEVICE_CODENAME)/mist_about.prop`
  in `mist_shiba.mk`. **Must be a `.prop` file**: `PRODUCT_*_PROPERTIES`
  lists split on whitespace, so any value with a space is truncated — Mist's
  own `ro.mistos.flavor` ships as `Cinnamon` instead of `Cinnamon Bun` for
  exactly this reason. Verify after build: `grep ro.mist. out/target/product/
  shiba/product/etc/build.prop`.
- **`MISTOS_MAINTAINER := chiranz`** in `mist_shiba.mk` → `ro.mistos.maintainer`
  (was empty). Build stays `UNOFFICIAL` (version.mk checks
  `OFFICIAL_MAINTAINERS`); that's fine.
- **Quick Tap was silently off.** `vendor/gms/gms_mini.mk` has
  `TARGET_SUPPORTS_QUICK_TAP ?= false` (full/pico default `true`), and
  `vendor/lineage/config/mist.mk` only adds `ColumbusService` (Proton's
  open-source Columbus client) when the flag isn't `false`, so the MINI
  choice dropped it — confirmed absent from `out/.../product_packages.txt`.
  Set `TARGET_SUPPORTS_QUICK_TAP := true` in `mist_shiba.mk`. This also
  adds the `quick_tap` sysconfig from GMS. Why it should work on Pixel 8:
  the blobs ship `vendor/etc/chre/columbus.so` with nanoapp ID
  `0x476f6f676c001019` — the exact `NANOAPP_ID` in ColumbusService's
  `CHRESensor.kt` — and `android.hardware.context_hub` is declared, so the
  app takes the CHRE path (its bundled `.tflite` files are 0-byte dummies,
  irrelevant here). **CONFIRMED WORKING ON-DEVICE by the user on the
  `...-20260917-1036` build** ("quick tap works"). For future debugging:
  `dumpsys contexthub | grep -i 476f6f676c001019` shows the nanoapp loaded;
  `logcat | grep -i columbus` shows `Initializing CHRE Sensor`. If the
  nanoapp ever isn't loaded, that's the contexthub HAL's preload
  list (no `preloaded_nanoapps.json` exists in the blob tree; the generic
  Pixel HAL handles it) — a different problem from the flag.
  **ColumbusService is NOT "Pixel Framework"**: stock Quick Tap lives inside
  SystemUIGoogle (`com.google.android.systemui.columbus`), which we don't
  ship; ColumbusService (ProtonAOSP/TheParasiteProject, GPL-3) is a
  from-scratch standalone client for the same nanoapp, so Quick Tap does
  not need the Pixel Framework port. Its README lists three frameworks/base
  commits it needs: `IStatusBarService.startAssist` and `toggleRecentApps`
  already exist in this tree; the third (ProtonAOSP `013c5904`, let
  privileged apps bind SystemUI's `TakeScreenshotService`) did NOT, so the
  "take screenshot" action would have silently failed — applied on
  2026-09-17 by changing that service's `android:permission` from
  `com.android.systemui.permission.SELF` to
  `android.permission.INTERACT_ACROSS_USERS_FULL` in
  `frameworks/base/packages/SystemUI/AndroidManifest.xml` (ColumbusService
  requests and is privapp-allowlisted for that permission). Because the
  module had never been in `PRODUCT_PACKAGES`, it had also never been
  compiled in this tree — a targeted `m ColumbusService` was run to prove
  it builds before relying on it: **compiled clean in 4m22s** (rc=0,
  `system_ext/priv-app/ColumbusService/ColumbusService.apk` produced).
  Note that a targeted `m <module>` works fine on this server even at load
  400+ when launched as `nohup setsid bash -c '... && m <module> -jN'` —
  much cheaper than a full build for "does this module even compile" checks.
- **`BYPASS_CHARGE_SUPPORTED` is not a flag in this tree.** GameSpace's
  "Bypass charging while gaming" toggle is shown when
  `Build.MANUFACTURER == "Google"` (or `persist.sys.battery_bypass_supported`
  / `persist.sys.ax_chg_bypass`), and the backend
  (`frameworks/base/.../wm/GameStateDispatcher.java`) just enables Lineage
  charging control via `HealthInterface.setEnabled()`. zuma's `common.mk`
  already configures the Pixel Lineage Health HAL with
  `charging_control_supports_limit/deadline=true` (Pixel `google_charger`
  `charge_stop_level`/`charge_start_level` sysfs). Nothing to set.
- **Other Mist flags checked for shiba, all already correct:**
  `TARGET_HAS_UDFPS := true` (zuma), `TARGET_EXCLUDES_AUDIOFX := true`
  (zuma; JamesDSP replaces it), `TARGET_BUILD_DEVICE_AS_WEBCAM := true`
  (zuma; `DeviceAsWebcam` is installed), `TARGET_ENABLE_BLUR` defaults on,
  `TARGET_INCLUDE_VIPERFX` unset (JamesDSP instead), `TARGET_INCLUDE_MOSEY`
  off, `TARGET_ENABLE_FP_OVERRIDE` skipped for shiba by mist.mk's own
  allowlist, `TARGET_GBOARD_KEY_HEIGHT` unset (optional Gboard key-height
  ratio; leave unless the user wants it).
- **Product-makefile parse order (explains the "late filter-out never
  works" rule):** `inherit-product` only records the parent path; the build
  parses the child product file (`mist_shiba.mk`) completely first, then
  each parent. So a plain `VAR := x` in `mist_shiba.mk` is visible to every
  parent's `ifeq`, while a `PRODUCT_PACKAGES := $(filter-out ...)` in the
  child runs before the parent's `+=` and can never remove it. Note the
  exception: plain `include` (not inherit) is immediate — `vendor/lineage/
  config/common.mk` `include`s `version.mk` (which pulls `gms_mini.mk`)
  while it's being parsed, whereas `mist.mk` is inherit-recorded and parsed
  later — that ordering is exactly how `gms_mini.mk`'s `?= false` beat
  `mist.mk`'s check.

## Things that are the user's decision, not bugs (state as of 2026-09-17)

- **Signing: the build is signed with AOSP `test-keys`** (`ro.build.tags=
  test-keys`, `userdebug` with Lineage's `ro.debuggable=0`). Test keys are
  public; any APK signed with them gets platform/system-signature
  privileges if installed. Standard practice for a daily driver is
  generating private release keys (`subject`/`make_key` under
  `~/.android-certs`, `PRODUCT_DEFAULT_DEV_CERTIFICATE`) and building
  `user`. **Switching keys changes the platform signature → requires a
  full `/data` wipe** and interacts with Tricky Store/PIF. Deliberately
  not done without the user's say-so.
- **The bundled Mist `Updater` app (`com.mist.updater`) is live and points
  at Mist's official OTA JSON** (`raw.githubusercontent.com/MistOS-Devices/
  official_devices/17/<PACKAGETYPE>/shiba.json`, package type from
  `ro.mist.packagetype`, which is `MINI` for this build). As of
  2026-09-17 the `MINI/shiba.json` channel returns 404 (only `GAPPS/`
  exists, listing an Oct-2025 Android 16 build), and `Utils.isCompatible`
  drops anything whose `timestamp` ≤ our `ro.build.date.utc`, so nothing
  is offered today. **Latent footgun:** if Mist ever publishes a newer
  official MINI shiba build, Updater will offer it and accepting would
  replace this custom build (kernel, Face Unlock fix, GCam, JamesDSP —
  everything). Options if that ever matters: drop `Updater` from
  `PRODUCT_PACKAGES`, or just never accept an OTA from the app.

## Reference repos used this session

Current `.repo/local_manifests/shusky.xml` pins (check this file directly
for the authoritative, up-to-date list — this is a snapshot as of this
writing):
- `crdroidandroid/proprietary_vendor_google_faceunlock` → `vendor/google/faceunlock`, revision `16.0`, gitlab remote
- `ionutsandroidbuilds/android_device_google_shusky` → `device/google/shusky`, revision `17.0`, github
- `ionutsandroidbuilds/android_device_google_zuma` → `device/google/zuma`, revision `17.0`, github
- `ionutsandroidbuilds/android_device_google_shusky-kernels` → `device/google/shusky-kernels`, revision `17.0`, github
- `TheMuppets/proprietary_vendor_google_shiba` / `_husky` → `vendor/google/shiba` / `husky`, revision `lineage-24.0`, github
- `ionutgherman/vendor_JamesDSP` → `vendor/JamesDSP`, revision `aidl`, github
- `ionutsandroidbuilds/proprietary_vendor_google_camera` → `vendor/google/camera`, revision `zuma`, gitlab

**General lesson on sourcing from external repos, established firmly this
session:** don't just trust a repo exists because the name matches — check
`pushed_at`/branch activity via the GitHub API (`api.github.com/repos/
<org>/<repo>` and `.../branches`) before trusting a candidate. An
abandoned, multiple-version-old fork (e.g. `Project-Mist-OS`'s own
`vendor_pixel-framework`, stuck at Android 15, untouched for over a year)
is a strictly worse choice than a more actively-maintained but
differently-named fork from another org, even when the "obvious" first
guess would be the project's own namesake repo. Also read recent commit
*messages*, not just file contents — they can reveal a feature being
actively dropped or added right around the exact commit you're
considering pinning to.

## Verification discipline (apply to every claim of "fixed")

Established through repeated correction across this whole session — a
build succeeding is not the same as a feature working, a plausible-sounding
sepolicy fix is not the same as a confirmed one, and even a fix verified
present in the loose `out/` directory is not automatically confirmed in
the actual flashable artifact. Before reporting anything as fixed:

1. **File/config presence isn't enough on its own** — grep
   `installed-files-*.txt` in `out/target/product/shiba/`, but also
   extract the actual value/content from the compiled artifact (see next
   points), and where an OTA payload is involved, extract from `payload.bin`
   directly (see "Verifying a build artifact" section), not just the loose
   `out/` directory.
2. **For kernels**: decompress and read the actual `Linux version` banner
   string, don't trust file size/checksum.
3. **For sepolicy rules**: the build succeeding at all is reasonably
   strong evidence a compile-time rule was accepted (a real conflict would
   hard-fail the build), but for anything with a live denial to fix,
   confirm the specific denial is actually gone from a fresh boot log —
   don't just trust that adding a plausible-looking `allow`/`dontaudit`
   line "should" work.
4. **For resource/config flags**: use `aapt2 dump resources <apk>` or
   `aapt2 dump xmltree <apk> --file AndroidManifest.xml` on the actual
   built/real APK to confirm compiled values or real manifest content —
   not just that a source edit was saved, and not just what AOSP's public
   source says a stock app *should* contain (Google's real shipped APK
   can differ, as the DocumentsUI `PreBootReceiver` case showed).
5. **For boot-image-related fixes**: check all three independently
   divergent things — raw header, AVB rollback index, AVB custom Props —
   and check them in the *actual OTA payload*, not just the loose `out/`
   directory (see dedicated section above).
6. **For anything with on-device runtime behavior**: only `adb logcat`/
   `dumpsys`/`getprop` on a real device gives a confirmed answer — but
   check the property-visibility gotcha above before trusting any
   `getprop`-based "it's missing" conclusion, and remember `grep -c` on a
   log tag counts lines, not distinct events (one Java exception can be
   20-40 stack-trace lines under the same tag).
7. **Logcat "absence" of a SystemUI boot-time line proves nothing on this
   device** (learned 2026-09-17): the `main` buffer rotates past
   SystemUI's entire startup window within ~2.5 minutes under normal load,
   while `events`/`kernel` retain far longer — so "the earliest line in
   the buffer is right after boot" is a false coverage signal. The valid
   check is the earliest surviving line from SystemUI's *own pid*
   (`logcat -d --pid=$(pidof com.android.systemui) | head -1`); if that is
   later than the moment you care about, use `dumpsys` (view hierarchy,
   dumpables) instead of logcat.
8. Don't declare victory on a single non-fatal-looking log line — chase it
   to see whether the component actually completes its job (e.g. "HAL has
   started successfully" *and* servicemanager confirming registration,
   not just the absence of an immediate crash).

## Documentation repo (GitHub)

Everything in this file plus all patches, new files, manifests and scripts
is published at **https://github.com/chiranz07/customrom/tree/main/mistos**
(commit 0669851, 2026-09-17). A local clone lives at `~/customrom_stage/repo`
(remote over SSH, key `~/.ssh/id_ed25519_github`, identity
`chiranz <chiranz07@users.noreply.github.com>`). After any future change:
re-export patches (the loop in `mistos/README.md` §3 / `~/mistos_patches_*`),
copy this HANDOFF.md into `mistos/`, commit, `git push origin main`.

## Publishing to SourceForge (set up 2026-09-17)

**Current project (moved 2026-09-17 evening): `chiranz`** —
https://sourceforge.net/projects/chiranz/files/ , SFTP path
`/home/frs/project/chiranz/`. Layout the user asked for:
```
shiba/  MistOS-...-shiba-UNOFFICIAL.zip
shiba/img/  boot.img  vendor_boot.img  vendor_kernel_boot.img  dtbo.img   (extracted from that zip's payload.bin via ota_extractor)
husky/  MistOS-...-husky-UNOFFICIAL.zip
husky/img/  (same four)
```
Notes: the SFTP dir only appears after the project's *Files* tool is
enabled in project admin; cross-project `rename` fails ("Failure") so a
move between projects is a re-upload; moving between folders inside one
project works with sftp `rename` (the web UI can't move). The older
project `mistos-shiba-unofficial` still holds a copy of the same layout.

Original project: `mistos-shiba-unofficial`, SourceForge user `chiranz`. A
dedicated SSH key (`~/.ssh/id_ed25519_sourceforge`, no passphrase) is
registered on the user's SourceForge account and `~/.ssh/config` has a
`Host frs.sourceforge.net` entry, so uploads from this server need no
password:
```bash
scp -o ServerAliveInterval=30 <zip> chiranz@frs.sourceforge.net:/home/frs/project/mistos-shiba-unofficial/
sftp chiranz@frs.sourceforge.net   # then: ls -l /home/frs/project/mistos-shiba-unofficial/
```
Run it `nohup setsid`-detached like the builds (a 2.86 GB upload took
~10 min at ~4–5 MB/s). The interactive `ssh` login itself fails with a
harmless "Could not chdir to home directory" — that's normal, only
scp/sftp/rsync are meant to work. The user asked for **no README** in
the file area. First release uploaded:
`MistOS-5.0-Alpha-17.0-MINI-20260917-1036-shiba-UNOFFICIAL.zip`
(SHA-256 `229ff6af…89f6`), size verified equal to local.

## Server/process hygiene notes

- Before any rebuild: `ps aux | grep -iE "mist_build_supervisor|soong_ui|
  ninja|ckati"` and `fuser ~/mistos/out/.lock` to confirm nothing is
  already running. Never launch a second build without confirming this.
- A `Bash` tool call is a separate shell process each time — don't expect
  `source build/envsetup.sh` from one call to make `lunch`/`get_build_var`
  available in a later, separate call.
- Windows users on the flashing side: PowerShell doesn't support `&&` the
  way bash does and has no native `grep` — use `;` or separate lines, and
  `Select-String -Pattern "..."` instead. Logcat output copied from a
  PowerShell redirect (`>`) into a file often comes out UTF-16LE with CRLF
  line endings — `iconv -f UTF-16LE -t UTF-8` before grepping it.
- Don't generate signing keys or do anything with real signing on this
  shared server without explicit user confirmation — test-keys are fine
  and confirmed still in use throughout this session.
- The user's daily-driver phone is the only test device, no test mule.
  Flashing/testing strategy is the user's call, not something to decide
  unilaterally. Bootloader/radio partition changes are categorically off
  limits without the user's own explicit, deliberate, fully-informed
  decision — never attempt speculatively "to see if it helps."
- The user may run their own separate live-device debugging agent (a
  Claude Code session with actual adb/device access, no root on `user`
  builds) connected via Remote Control cross-session messaging. If so:
  reply to the exact `from=` address of an incoming cross-session message,
  not a display name (display names can silently stop resolving even
  mid-session — the underlying `bridge:session_<id>` address is more
  reliable, though it too can go stale if that session restarts — check
  `ListAgents` again if a send returns HTTP 409). Treat all of that
  agent's findings as claims to verify from source where possible, not
  settled facts — and expect the same scrutiny in return; this
  collaboration self-corrected several real mistakes on both sides this
  session by staying skeptical of each other's claims rather than
  compounding them.
