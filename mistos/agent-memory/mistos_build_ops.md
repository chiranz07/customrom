---
name: mistos-build-ops
description: Operational gotchas for running the Mist-OS Pixel 8 (shusky/shiba) ROM build on the shared multi-tenant server
metadata: 
  node_type: memory
  type: project
  originSessionId: b533daf7-cfc3-433c-b8d7-c4f36d463653
  modified: 2026-09-16T13:13:27.398Z
---

Building Project Mist-OS (Android 17) for Pixel 8 (shiba, `mist_shiba-aosp_current-userdebug`) in `~/mistos` on a heavily shared 96-core/251GB server (dozens of concurrent tenants, load average routinely 90-280+, swap frequently fully exhausted from OTHER users' processes).

**Backgrounded builds must be launched via `setsid` + `nohup` + `disown`, never left as a plain `run_in_background` Bash monitor.** The harness's own "system is running low on memory" protection kills tracked `run_in_background` Bash tasks fairly often on this host (roughly every 1-2 minutes when the host is under memory pressure), but this only kills the *monitoring* wrapper, not a properly `setsid`-detached child process tree, which survives independently.

**Why this matters / a costly mistake made once:** after one such "killed" notification, a quick `ps aux | grep soong_ui` immediately after came back empty, which was wrongly read as "the build died." In fact the check ran ~5 seconds before `soong_ui` had even forked (envsetup+lunch+installclean overhead) — the build was alive the whole time. Relaunching a second build "to replace" the first caused two `mist b` invocations to fight over the same `out/.lock`, producing spurious lock-timeout failures.

**How to apply:** before concluding a build actually died, use `ps -ef --forest` (or `ps -o pid,ppid,lstart,etime,cmd`) and check the process's actual start/elapsed time, not just a bare grep — give it real margin, especially right after just launching. Check `fuser ~/mistos/out/.lock` / `lsof ~/mistos/out/.lock` to see if a `soong_ui` is still legitimately holding it before assuming it's stale. Only kill and relaunch after confirming via elapsed time that the process could not still be starting up.

A self-relaunching supervisor script now lives at `~/mist_build_supervisor.sh` (arg: job count) — it retries automatically on a build that dies with no `FAILED:` marker in its log (treated as a premature/OOM-style kill) but stops and writes `~/mist_build_final_status.txt` on either success or a real `FAILED:` compile error. Always launch it via `setsid nohup bash ~/mist_build_supervisor.sh <jobs> > ~/mist_build_supervisor.log 2>&1 < /dev/null & disown`, and never run a second instance concurrently — check `ps aux | grep mist_build_supervisor` and `fuser ~/mistos/out/.lock` first.

User ([user email]) got explicit admin authorization on this server to use all 96 cores for the build (not just the conservative `-j16` the original HANDOFF.md suggested for `repo sync`), so the supervisor's default job count is 96. See [[mistos_rom_build]] for the overall build goal/handoff context.

**A `FAILED:` line in the build log is not automatically a real compile error.** When ninja itself gets SIGKILLed (OOM), whatever action was still in-flight prints its own `FAILED: ...` block ending in `error: action cancelled when ninja exited` — that's a symptom of the kill, not a genuine compiler diagnostic. The real signal is a line like `ninja failed with: signal: killed` earlier in the same log. The supervisor script now checks for that signal-kill signature *before* treating any `FAILED:` line as a real failure (grep `ninja failed with: signal: (killed|terminated)` first). Before this fix, one such false positive wrongly stopped the retry loop when the build was actually at 99% complete (21255/21291 targets) — always check for the `signal: killed` line yourself if a "real failure" report looks suspicious (e.g. happens very late/near completion, or the actual error text is just "action cancelled when ninja exited" rather than a compiler diagnostic).
