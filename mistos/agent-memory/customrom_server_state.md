---
name: customrom_server_state
description: State of the ROM build server and repos after the 2026-09-18 reset (what survived, what is gone, where everything lives)
metadata:
  type: project
---

Build server state checked 2026-09-18 ~14:40 UTC, after the user "kinda did a reset". The machine itself is the same
96-core / 251 GB / 18 TB box (1.8 TB free, RBE at /srv/rbe), not a fresh one.

**Survived:** SSH keys `~/.ssh/id_ed25519_{github,sourceforge}` (both verified working), `~/customrom_stage/repo` at
origin/main `1c26cf7` (its working tree had been emptied — restored with `git checkout -- .`), `~/voltage` (106 G,
no `out/` artifacts, signing keys gone), `~/yaap` (75 G, ~73 % built), `~/kernel` (2 G),
`~/pixel-framework_rising_sixteen`. All SourceForge uploads intact under project `chiranz`
(`mistos/{shiba,husky}`, `pixelos/…`, `voltage/…`).

**Gone:** `~/mistos` and `~/pixelos` trees (deleted earlier on request, before the reset), `~/shusky-kernels-prebuilt`,
Voltage's `vendor/voltage-priv/keys` (so Voltage OTA-compatible rebuilds need a fresh key set + clean flash), and
Claude's memory dir — restored from `mistos/agent-memory/` in the GitHub repo.

**How to apply:** github.com/chiranz07/customrom is the authoritative state: `mistos/README.md` = procedure,
`mistos/HANDOFF.md` = why, `mistos/FEATURES.md` = per-feature recipes, `voltage/VOLTAGE.md`, `pixelos/PIXELOS.md`.
Rebuilding Mist means a fresh ~450 GB `repo sync` per `mistos/README.md` §2–§5. See [[mistos_rom_build]],
[[mistos_build_ops]], [[feedback_never_delete_published_builds]].
