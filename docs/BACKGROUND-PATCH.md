# Background stability patch

This patch addresses confirmed code defects in lock-screen lyric rendering. It does
not establish the cause of the reported Spotify termination: no matching iOS crash
report, device test, or energy/memory trace was available.

- Speculative preview/video generation now requires an actual system request in
  the last 60 seconds, including the current line. Track changes no longer invent
  requests. Without demand, a lightweight artwork descriptor is published so its
  callbacks can resume rendering when the lock screen needs it. Preview demand
  does not start video generation. Already-running renders may finish.
- Clearing lyric artwork invalidates queued speculative work even before the first
  artwork has been published.
- Temporary Objective-C objects are drained after each generated karaoke/vinyl
  frame instead of accumulating across the full encoding loop.
- Failed word-timing or motion-overlay allocations no longer lead to writes
  through null pointers. Missing optional blur buffers disable blur; a missing
  mandatory dimming buffer fails the motion render and uses the existing fallback.

Validation in Linux:

```
cc -std=c11 -Wall -Wextra -Werror tests/lockscreen/demand.c -o /tmp/spmod-demand-test
/tmp/spmod-demand-test
bash scripts/check-layers.sh
git diff --check
```

These passed. The demand test covers idle launch, independent preview/video
requests, expiry, wake, and invalid/rewound clocks. The Apple rendering harness
`bash harness/lyrics-clip/build.sh` was attempted but could not run because
`xcrun` is unavailable. Objective-C compilation, allocation-failure injection,
encoding and on-device behavior remain unverified.

Device verification (iOS 26+, native or redesigned UI): build the IPA from
`patched`, install and restart it. Enable lock-screen animated lyrics. Check first
appearance, track changes, pause/resume, then play for at least 10 minutes with
the screen asleep and wake it again. Lyrics should resume. Repeat in another app,
and once with lock-screen lyrics disabled. Capture the timestamp and matching
Spotify `.ips` or JetsamEvent report if it terminates again.

## Animated player pause/resume

The redesigned player's animated Canvas/cover already used AVPlayer pause/play
for music pause. It now also remembers the current clip's exact CMTime before
its view is removed, and seeks back before resuming a recreated view. The key
includes the track and local video URL. Only one position is held in process
memory; a different clip starts fresh and app relaunch clears the memory.
Settings previews do not overwrite the real player's position. While the same
view remains alive, pausing leaves its decoded frame visible. After recreation,
the poster can appear briefly while AVFoundation decodes the restored frame.

Additional defects fixed:

- The view's copied `gaveUp` callback strongly captured the view itself, keeping
  the AVQueuePlayer/looper alive after removal. It now uses a weak reference and
  is cleared when the view retires.
- A departing view could resume during its fade because it still observed player
  state/transition notifications. Retired views now stay paused.
- The video now pauses synchronously on WillResignActive rather than scheduling
  a lifecycle check for later. Becoming active does not resume music-paused video.
- Invalid poster dimensions no longer reach the aspect-ratio calculation.

Lock-screen limitation: MPMediaItemAnimatedArtwork exposes asset callbacks and
an artwork ID, but no readable playhead or pause/seek control for the system's
video player. Exact frozen-frame/resume synchronization with that player is not
implemented, and the native Spotify video UI is unchanged. No estimated timeline
or background video encoder was added.
References:
https://developer.apple.com/documentation/mediaplayer/mpmediaitemanimatedartwork
https://developer.apple.com/documentation/mediaplayer/providing-animated-artwork-for-media-items

Validation: layer and whitespace checks pass. Linux cannot compile/run this
UIKit/AVFoundation/Logos path; physical-device playback remains unverified.
On iOS 26+ with Redesigned UI and Animated background: pause mid-Canvas, leave
and reopen the player, background/foreground the app, then resume. The video
should hold its frame and continue, without counting paused/background time.
Also toggle Animated off/on on the same track, change tracks, switch Low Power
Mode on/off, and relaunch. Confirm no old video resumes during the outgoing fade.
Use Instruments Allocations across repeated track changes to verify removed
SGRPlayerMotionView instances are released.
