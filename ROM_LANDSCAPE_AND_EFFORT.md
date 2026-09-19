# ROM landscape and the cost of running one

Written 2026-09-19, after the Mist-OS / VoltageOS September builds shipped. Two
questions were on the table: **what else can we build for Pixel 8?** and **what would
it take to run a ROM of our own?**

Everything in the tables below was verified live with `git ls-remote` and by cloning
device trees on 2026-09-19 — not taken from release threads or forum posts. Branch
state moves; re-check before acting on any row.

---

## 1. Buildability checks — how to do them

The only two questions that matter for "can we build ROM X for shiba/husky":

1. **Is every repo the manifest references public, on the branch it claims?**
   A ROM can have a public manifest and still be unbuildable if its core repos are private.
2. **Is there a `device_google_shusky` tree on a matching branch?**
   Pixel 8 (shiba) and Pixel 8 Pro (husky) share the `shusky` tree. No tree = a porting
   project, not a build.

Script for (1) — resolve each `<project>` to a URL and check the branch exists:

```bash
export GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true
git ls-remote --heads "$url" "$rev" | grep -q "refs/heads/$rev" && echo OK || echo MISSING/PRIVATE
```

`GIT_TERMINAL_PROMPT=0` is load-bearing: without it a private repo hangs on a
credential prompt instead of failing.

For (2), search GitHub rather than guessing org names — device-tree orgs are named
inconsistently (`FooOS-Devices`, `FooOS-devices`, `android_device_…` vs `device_…`):

```bash
curl -s "https://api.github.com/search/repositories?q=shusky+in:name&per_page=100&page=1"
```

That one query returned 101 repos and found every ROM's tree in one pass, including
several that guessing had missed.

---

## 2. Results — Android 17

| ROM | Manifest branch | shusky tree | Tree last commit | Verdict |
|---|---|---|---|---|
| **Mist-OS** | `17.0` | (we use LineageOS `lineage-24.0`) | — | **Building. Maintained by us.** |
| **VoltageOS** | `17` | (we use LineageOS `lineage-24.0`) | — | **Building. Maintained by us.** |
| **CaesiumOS** | `17` | `CaesiumOS-Next/device_google_shusky` `17` | 2026-08-31 "shusky: Adapt to AOSP/CaesiumOS Next" | **Buildable, unexplored** |
| **AICP** | `x17.0` | `AICP/device_google_shusky` `x17.0` | 2026-07-09 "Update to CP2A.260705.006" | **Buildable, unexplored** |
| PixelOS | `sixteen` (no 17) | — | — | No A17 |
| DerpFest | `17` | tree stops at `16.2` | — | Needs a tree port |
| RisingOS Revived | `seventeen` | tree stops at `sixteen` | — | Needs a tree port |
| **AlphaDroid** | `alpha-17.0-gitlab` | — | — | **NOT BUILDABLE — see §4** |
| **PenguinOS** | `celerity` | — | — | **Qualcomm only — see §5** |

Both CaesiumOS and AICP trees were cloned and confirmed to carry real
`aosp_shiba.mk` / `aosp_husky.mk` products, not stubs. AICP's is on the same CP2A
stamp our own builds use.

## 3. Results — Android 16

Verified: ROM has an A16 manifest branch **and** a shusky tree on a matching branch.

| ROM | Manifest | shusky tree | Tree last push |
|---|---|---|---|
| **LineageOS** | `lineage-23.2` | `LineageOS/android_device_google_shusky` | 2026-09-15 |
| **AxionAOSP** | `lineage-23.2` | `AxionAOSP-devices/android_device_google_shusky` | 2026-09-18 |
| **Evolution X** | `bka` | `Evolution-X-Devices/device_google_shusky` | 2026-08-24 |
| **AICP** | `w16.2` | `AICP/device_google_shusky` | 2026-07-25 |
| **DerpFest** | `16.2` (at `DerpFest-AOSP/android_manifest`) | `DerpFest-Devices/device_google_shusky` | 2026-07-05 |
| **Alch3myOS** | not located | `Alch3myOS-Devices/device_google_shusky` `16` | 2026-06-08 |
| **crDroid** | `16.0-qpr1` | `crdroidandroid/android_device_google_shusky` `16.0` | 2026-05-03 |
| **Infinity-X** | `16-QPR1` | `Infinity-X-Devices/device_google_shusky` `16.2` | 2026-02-08 |
| RisingOS Revived | `sixteen` | `RisingOS-Revived-devices/…` `sixteen` | stale (2025-10) |

Own-ecosystem, A16, official shusky support: **GrapheneOS** (`16-qpr2`) and
**CalyxOS** (`android16-qpr2`). Both buildable; both have clear positions on
third-party redistribution — see the GrapheneOS note in `voltage/VOLTAGE.md` §10.

**No Pixel 8 tree at all:** PixelOS, SuperiorOS, Project Matrixx, LMODroid, YAAP,
CherishOS. (PixelOS ships A16 but has no public shusky tree — our own Sept 2026
PixelOS build used LineageOS trees, see `pixelos/`.)

Naming note: several ROMs use word-branches (`sixteen`, `seventeen`) or Android
dessert codes (`bka` = Baklava/16, `cnb` = Cinnamon Bun/17, `vic` = Vanilla Ice
Cream/15). A numeric grep misses all of them — always dump the full branch list.

---

## 4. AlphaDroid — why Android 17 is not buildable

Re-verified 2026-09-19 (the same conclusion as the 2026-09-18 check).

- `AlphaDroid-Project/manifest` does have `alpha-17.0-gitlab`.
- That manifest routes 17 projects to `gitlab.com/alphadroid-project` at
  `refs/heads/alpha-17.0`.
- **13 of those 17 are private**, including every core repo: `frameworks_base`,
  `build_make`, `build_soong`, `system_core`, `bootable_recovery`, `vendor_alpha`,
  `device_alpha_sepolicy`, and the `packages_apps_*` set.
- Only 4 are public, all vendor blob repos (`vendor_pixel_gms-17`,
  `vendor_pixel_launcher`, `vendor_pixel_sounds`, `vendor_pixel_themepicker`).
- The GitHub mirrors stop at `alpha-16.2`; `frameworks_base` has no `alpha-17.0`
  branch there at all. The GitLab group also contains
  `android_frameworks_base-deletion_scheduled-86488482`.

**Android 17 is in private development. Only `alpha-16.2` (Android 16) is public.**

## 5. PenguinOS — buildable, but not for Pixel

Checked 2026-09-19 at `github.com/Project-PenguinOS/manifest`, branch `celerity`.

**The manifest is sound.** 1,286 projects; all 91 non-AOSP repos are public and carry
the branch they claim; AOSP tag `android-17.0.0_r1` exists; CLO repos reachable. Zero
private holes — the opposite of AlphaDroid.

**But it is a Qualcomm-only tree:**

- The system tree is **CLO** (`git.codelinaro.org/clo/la`, `ks-aosp.lnx.17.0.r1-rel`),
  Qualcomm's AOSP fork, not plain AOSP.
- Every device path in the manifest is `device/qcom/*` — blair, kalama, lahaina,
  pineapple, sun, taro. No Tensor anything.
- `vendor/aospa/products` lists 32 devices, all Xiaomi / OnePlus / Nothing / Sony.
  No Pixel, no shiba, no husky.
- The org's 38 repos contain no device tree for any phone.

Base is AOSPA (Paranoid Android). First manifest commit 2026-09-18 — a brand-new
project. Getting shiba onto it would mean porting a Tensor device tree, blobs and
kernel onto a Qualcomm-oriented CLO tree plus writing `aospa_shiba.mk` — weeks of
porting, not a build.

---

## 6. What it would take to run our own ROM

### What a ROM actually is

| Piece | State as of Sept 2026 |
|---|---|
| Manifest repo + forked repos | **Have it.** 152 files patched across 12 repos for Mist (86 in `frameworks/base` alone) |
| Device trees | **Have it.** LineageOS shusky |
| `vendor/<rom>` — branding, product makefiles, version scheme | Missing |
| Signing keys + release process | **Have it.** Done for both ROMs |
| OTA server + updater app | Missing — and `Updater` is deliberately gated out of Mist (`FEATURES.md` §18) |

The Mist fork *is* a ROM in everything but name. The gap is branding and OTA.

### Getting to "it boots with my name on it": ~1 weekend

Fork a LineageOS manifest, copy `vendor/lineage` → `vendor/<name>`, rename the
makefiles and version string, swap boot animation / wallpapers / accent / About page,
build. That is what most new ROMs are on day one.

### The real cost is maintenance

| Event | Frequency | Cost |
|---|---|---|
| Security patch rebase across 12 repos | monthly | 2–4 hrs |
| QPR bump (Google rewrites SystemUI internals; the 86-file `frameworks/base` patch conflicts) | quarterly | 1–3 days, sometimes a week |
| New Android version — effectively re-porting every feature | annual | 2–4 weeks |
| Each additional device (blobs, kernel, thermals, its own bugs) | — | +5 hrs/month, **and you must own the hardware** |

**Steady state, solo, 2 devices: 15–25 hrs/month**, spiking past 60 on a QPR. Most
ROMs die in month four, when a QPR lands during a busy week.

### What is missing beyond the code

1. **A reason to exist.** 40+ ROMs already. "Lineage + Pixel features" is Mist,
   Evolution X, crDroid and Axion already. Without a thesis nobody flashes it.
2. **An OTA channel.** Without one, users clean-flash monthly. They will not.
3. **A second maintainer.** Solo ROMs die when the maintainer gets busy.
4. **Support presence.** Answering a Telegram group is more hours than building.

Theses that would justify it: *"Pixel 8 done properly"* (one device family, every
Pixel feature genuinely working — `FEATURES.md` is already that pitch);
*"vanilla with real face unlock"*; *"LTS past Google's EOL for shusky"*.

---

## 7. What changes with an AI agent maintaining it

Grounded in the Sept 17–19 sessions, where an agent did most of the work. Both
columns are real.

**Where the agent was decisive**

- VoltageOS GApps "no space": one missing `-include` line in a 450 GB tree. Found in
  about an hour; a human hunt is days. (`voltage/VOLTAGE.md`)
- The Megvii/Sense face-unlock hijack — found in *both* ROMs, same root cause, would
  have shipped silently. (`mistos/FEATURES.md` §2)
- `DefaultPermissionGrantPolicy`: read the platform source, proved the
  POST_NOTIFICATIONS fix was impossible on this blob, and stopped the chase.
  (`FEATURES.md` §17)
- Verified 1,286 PenguinOS projects in ~10 minutes (§5 above).
- `FEATURES.md` itself — 20 documented root causes — is agent-written, and is the
  most valuable artifact in this repo.

**Where the agent failed, in the same window**

- **Deleted `device/google/shusky/sepolicy/vendor/genfs_contexts`** while reverting an
  unrelated experiment, killing GNSS and wireless charging, and shipped it. The
  **on-device agent** caught it, not the build agent. (`FEATURES.md` §14)
- Invented the `/sys/class/pps` verification premise without reading the driver — cost
  a device test session. (`FEATURES.md` §14, last bullet)
- Two wrong root-cause theories on the AOD Now Playing behaviour before a human
  observation settled it. (`FEATURES.md` §19–20)
- Claimed the PowerStats HAL was undeclared. It is declared. (`voltage/CHANGELOG.md`)

**Three confident-wrong answers in one session.** That is the planning number.

### Revised effort

| Task | Solo | Agent-assisted |
|---|---|---|
| Monthly security patch | 2–4 hrs | ~1 hr (agent rebases, human reviews + flashes) |
| QPR bump | 1–3 days | ~1 day, mostly human testing |
| New Android version | 2–4 weeks | ~1 week |
| Root-causing a bug report | 2–8 hrs | ~1 hr |
| Docs / changelog / release notes | hours | ~0 |
| **Hardware testing** | — | **does not compress** |

**15–25 hrs/month → roughly 6–10.** A genuine 2–3x, not 10x.

It does not go further because: testing needs a human with the phone; scope judgment
(drop Quick Switch, block OTA, don't bundle the GrapheneOS store) was human every
time and was right every time; and trust does not delegate — nobody joins a Telegram
group run by a bot, and a person has to answer when a build breaks a phone.

### The prerequisite: a verification harness

The single most important finding of these sessions is that **the on-device agent
caught a regression the build agent introduced and had already shipped.**

That pattern is what makes agent maintenance viable. Split it:

1. **Build agent** — sync, rebase, resolve conflicts, build, triage logs, write the
   changelog, prepare uploads.
2. **Device agent** — scripted post-flash sweep: SELinux denial inventory, service
   respawn loops (`init.svc.*` ETIME vs uptime), GNSS fix from the *gps* provider (not
   fused), wakelock rates, thermals, package presence. `FEATURES.md` §19 is a worked
   example of exactly this sweep.
3. **Human** — flash, eyeball, decide, answer users.

**With that harness, an agent can run the cycle and the human is a reviewer. Without
it, an agent running unsupervised ships the GNSS regression to users — which is not
hypothetical, it is what happened on 2026-09-18.**

Build the harness before the ROM.

---

## 8. Conclusion as of 2026-09-19

No new ROM for now. Maintaining Mist-OS and VoltageOS well is worth more than being
ROM #48. If that changes, the order is: **thesis → verification harness → branding
and OTA → ROM.**

Unexplored and worth a look if we want a third ROM on Android 17: **CaesiumOS** (`17`,
tree adapted Aug 2026) and **AICP** (`x17.0`, same CP2A stamp we use). Neither has had
a buildability sweep of the kind in §5.
