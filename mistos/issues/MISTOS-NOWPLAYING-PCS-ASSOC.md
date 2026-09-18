# MISTOS-NOWPLAYING-PCS-ASSOC — Now Playing blocked from Private Compute Services by allow-association allowlist

Tracker entry written by the device-side agent (rom-4c, session_013r4JxdvG95YfarQsRt7iDn) on 2026-09-18, filed verbatim.
Source fix: `patches/rom/device_google_zuma.patch` (Mist) and `../pixelos/patches/device_google_zuma-lineage-24.0.patch` (PixelOS).
Fixed builds: Mist shiba 20260918-0517, PixelOS shiba 0535 / husky 0608. Mist husky 1816 still affected.

STATUS:    RESOLVED — fix verified on device
SEVERITY:  High (feature completely non-functional)
AFFECTED:  MistOS 5.0-Alpha 17.0, Pixel 8 (shiba). Build 1804 / CP2A.260805.005 broken. Fixed in CP2A.260605.016 (20260918-0517).
REPORTED:  2026-09-18
AREA:      device/google/zuma — sysconfig / package associations

## Symptom
Now Playing never identifies any music. No lock-screen pill, no notification, empty history. In-app "Use Now Playing" toggle accepts taps but will not latch (checked stays false, backing datastore never written, app logs nothing). Settings > Sound & vibration > Now Playing entry absent.

## Root cause
/product/etc/sysconfig/allowlist_com.google.android.as.xml (source: device/google/zuma/allowlist_com.google.android.as.xml, SPDX 2022 LineageOS) restricted Private Compute Services to two callers:

    <allow-association target="com.google.android.as.oss" allowed="com.google.android.as" />
    <allow-association target="com.google.android.as.oss" allowed="com.google.android.aicore" />

Google split Now Playing out of com.google.android.as into com.google.android.apps.pixel.nowplaying. Mist ships that app (/product/app/NowPlayingPrebuilt + default-permissions_nowplaying.xml + preinstalled_packages entry) but never allowlisted it, so ActivityManager refused every bind:

    W ActivityManager: Service lookup failed: association not allowed between packages
    com.google.android.apps.pixel.nowplaying (uid=10392) and com.google.android.as.oss (uid=10365)

Cold start showed 3 attempts with 1s/2s exponential backoff, then give-up. Init is gated on that bind; once abandoned, the preference datastore is never writable — hence the dead toggle. The allowlist file predates the app split.
Stock comparison (CP2A.260605.012 factory product.img): stock defines NO allow-association with target="com.google.android.as.oss" at all, i.e. PCS is unrestricted on stock.

## Fix
Removed both target="com.google.android.as.oss" lines from device/google/zuma/allowlist_com.google.android.as.xml, mirroring stock (PCS unrestricted, so any PCS client works). Chosen over per-app allowances. Verified in built image: grep -c 'target="com.google.android.as.oss"' = 0.
NOT NEEDED: <allow-association target="com.google.android.as" allowed="...nowplaying" /> — denial census proved the split app never binds ASI, only PCS.

## Verification (controlled comparison)
User flashed, confirmed working BEFORE updating apps, then updated Play apps; still working. Both states captured.

    Pre-update:  nowplaying 315   / ASI C.0.playstore.pixel8.881198773
    Post-update: nowplaying 52709 / ASI C.6.playstore.pixel8.961955194   <-- EXACTLY the versions that failed on 1804
    Both states: 0 association denials, detection works, lock-screen pill renders.

Same app versions that failed on 1804 succeed on the fixed build. Only delta is the allowlist change.
Evidence post-update:

    soundtrigger_middleware: model 9f6ad62a-1f0b-11e7-87c5-40a8f03d3f15 LOADED + ACTIVE, dataSize 22936, owner uid 10347 com.google.android.as
    11:57:16.855 StHal::SoundTriggerHal: received AmbientMusic recognition
    11:57:16.896 AmbientMusicDetector [3475=ASI]: Running on-device song recognition.
    11:57:20.024 AmbientMusicDetector: last-matched track ID from shard
    11:57:23.751 MusicRecognitionHandler: Music recognized
    11:57:23.788 AmbientIndication [2163=SystemUI]: Showing ambient indication.
    Lock-screen screenshots: "505 - Arctic Monkeys" (pre-update), "Sailor Song - Gigi Perez" (post-update)

## Ruled out during investigation (evidence-backed, do not re-investigate)
- Permissions — split app declares only 7, all granted; does not request RECORD_AUDIO. allow-association is package visibility, not a permission.
- AppOps — RUN_ANY_IN_BACKGROUND / RUN_IN_BACKGROUND / POST_NOTIFICATION all "No operations. Default mode: allow".
- App Manager tracker blocking — /data/system/ifw/ empty, AM rule store files/conf/ empty, zero blocked components.
- Microphone / ASI — ASI holds RECORD_AUDIO + CAPTURE_AUDIO_HOTWORD + CAPTURE_AUDIO_OUTPUT.
- Network / DNS — music-iq manifest reachable HTTP 200, 77GB free, no netpolicy restriction, NextDNS not blocking.
- SystemUI AmbientIndication port — correct; registers receivers at runtime while keyguard shows (manifest-only queries give false negatives).

## Architecture note
com.google.android.apps.pixel.nowplaying is never in `ps` — before or after the update. Detection, shards and the AMBIENT_INDICATION_SHOW broadcast all live in ASI; SystemUI renders. The split app is a history/settings front end only, yet its blocked PCS bind was still fatal — ASI appears to gate Now Playing availability on it initialising.

## Follow-up 1 — OPEN — cosmetic — MISTOS-NOWPLAYING-SETTINGS-TILE
ASI updates disable their own Settings tile activities. After C.0 -> C.6, user-0 disabledComponents contains AmbientMusicSettingsActivity, AmbientMusicNotificationsSettingsActivity (and HearingHealthSettingsActivity). Result: "Now Playing" disappears from Settings > Sound & vibration after every ASI update. Feature still works; only the shortcut is lost. Google-side behaviour, not a Mist bug — but Mist ships AOSP/Lineage Settings which has no built-in entry and depends entirely on ASI's injected tile.
Suggested fix: give Settings its own entry -> com.google.android.as/com.google.intelligence.sense.ambientmusic.NowPlayingAmbientMusicSettingsActivity (stays enabled) or com.google.android.apps.pixel.nowplaying/.settings.MainSettingsActivity.
Workaround not possible via shell: pm enable refused with "Shell cannot change component state" on this build.

## Follow-up 2 — OPEN — trivial
POST_NOTIFICATIONS ships denied on com.google.android.apps.pixel.nowplaying. Add to default-permissions_nowplaying.xml (currently present with fixed="false").

## Follow-up 3 — INFO
Same allowlist previously denied com.google.android.inputmethod.latin -> as.oss and as.oss -> com.google.android.tts, so Gboard/TTS PCC features were broken identically. The stock-mirroring removal fixes those too — worth a regression check.

## Device state after testing
Root unavailable — dirty flash replaced the KernelSU-patched boot (su not found). `svc power stayon true` and screen_off_timeout=600000 were set during testing and should be reverted.
