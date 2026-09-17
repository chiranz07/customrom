---
name: feedback-dont-stop-builds-unasked
description: "Never stop/pause a running build on my own initiative (e.g. because of a server broadcast); only on the user's explicit instruction"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: b533daf7-cfc3-433c-b8d7-c4f36d463653
  modified: 2026-09-17T14:56:59.487Z
---

Do not stop, pause, or throttle a running build unless the user explicitly asks. The user has an agreement with the server admins to use up to 96 cores; admin broadcast messages ("don't start builds yet", "maintenance") are sent to everyone and are not directed at this user's builds.

**Why:** On 2026-09-17 I killed a 20-minute-old build after the user merely forwarded a broadcast and asked me to "check the build status" — they had not asked me to stop, and it cost them build time. Their words: "did i ask you to stop - why did you?"

**How to apply:** When forwarded a broadcast or asked for status, report the facts (is it running, load, what a reboot would do) and leave the build alone. If a reboot kills it, relaunch it (builds are incremental). Job count stays at the agreed 96 unless the user says otherwise. See [[mistos-rom-build]].
