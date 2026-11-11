# Background stability — patch v2

Branch: `patch-v2`, created from `patched`. `patched` and `main` are unchanged.

## Changes

- **Core Graphics / Core Text allocation failures:** lock-screen lyric and Fluid rendering now stop or fall back when mandatory bitmap contexts, text frames, or images cannot be created. Release nullable images only when present; check pixel buffer locks and video dimensions before accessing their data.
- **Bounded video operations:** shared `SGVideoEncodeSafety.h` replaces infinite AVAssetWriter backpressure / completion waits with 30-second ready and 60-second finish limits. Async AVAssetTrack loading in Canvas shaping and lyric overlay is capped at 30 seconds; stale or inaccessible media fails gracefully. **These are failure fallbacks, not guarantees about system suspension**.
- **Per-frame object lifetime:** Fluid/Fill writers now drain temporary Objective-C allocations each frame; karaoke/vinyl had already received this on `patched`.
- **Lock-screen timer:** while Spotify is active or the lock screen actually requested animation in the last 60 seconds, lyric updates stay at 250 ms. Without demand while backgrounded, updates slow to once a second. A new system request immediately restores 250 ms. This is a power and CPU mitigation; timing must be tested on device.
- **Demand header:** `#pragma once` is now a real preprocessor directive instead of being attached to a comment.

## Remaining limitations and risks

- Video generation requested by iOS may continue to run after its source becomes obsolete **once encoding has started**. A robust in-flight cancellation API has not been added, as doing so would require coordinating the writer's lifecycle, Apple callbacks and the serial rendering queues.
- These changes cannot prevent iOS from legitimately suspending or terminating an application. A Jetsam kill, watchdog kill, uncaught exception, and Spotify's own playback/background behavior require different diagnosis.
- 30/60-second timeouts are defensive defaults; some slow devices can require tuning. A failed render falls back rather than waiting forever.
- No physical iOS device/Apple SDK compilation or iPhone background playback test was performed for this branch during this change. The successful GitHub Actions IPA build found in the prior audit was on **patched**, *not patch-v2*.
- Contexts used outside these modules (audio DSP, Jam, lyrics providers, etc.) were not all exhaustively audited.

## Verification plan

1. Trigger **Build SPMod IPA** with branch `patch-v2` and ensure iOS/Logos compilation succeeds.
2. Test normal playback for 30 minutes on an iPhone; lock the screen; switch to another app; return; try pause, resume and skip rapidly.
3. In the lock screen choose animated lyrics, Fluid, Fill and Canvas in turn. Each should appear and move; the wallpaper/clip should not freeze indefinitely after a background transition.
4. Under Low Power Mode and Reduce Motion, repeat transitions. Confirm settings previews are released after dismissal.
5. Simulate low-memory or allocation-failure conditions with Instruments. Ensure missing images fall back rather than causing an EXC_BAD_ACCESS.
6. Force slow, invalid or unreadable clip assets and interrupted encoders. Verify that waits time out, partial files are not promoted to complete assets and playback continues.
7. Compare idle CPU time with no lock-screen artwork demand to `patched`; monitor Energy Log and Allocations. Confirm lyric timing never drifts perceptibly.
8. Obtain Spotify `.ips` crash or `JetsamEvent` logs for remaining background exits, and match timestamps to system and app logs.

No live cancellation or iOS runtime stability guarantee is claimed by these changes.
