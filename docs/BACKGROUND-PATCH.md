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
