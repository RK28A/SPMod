#include <assert.h>
#include "../../tweak/Sources/Shared/LockScreenLyrics/SGLyricsDemand.h"

int main(void) {
    // Launch and track changes without system requests must not render videos.
    double preview = 0, video = 0;
    for (double now = 100; now < 1000; now += 0.25) {
        assert(!SGLyricsHasRecentDemand(now, preview));
        assert(!SGLyricsHasRecentDemand(now, video));
    }
    // A preview request must not wake the video encoder.
    preview = 1000;
    assert(SGLyricsHasRecentDemand(1001, preview));
    assert(!SGLyricsHasRecentDemand(1001, video));
    // Recent requests warm subsequent lines, then expire while the phone sleeps.
    video = 1002;
    assert(SGLyricsHasRecentDemand(1062, video));
    assert(!SGLyricsHasRecentDemand(1062.25, video));
    assert(!SGLyricsHasRecentDemand(2000, preview));
    // A new request after wake resumes rendering, without restarting the app.
    video = 2000;
    assert(SGLyricsHasRecentDemand(2000, video));
    // Clock changes and invalid timestamps must not enable unbounded prewarming.
    assert(!SGLyricsHasRecentDemand(1999, video));
    assert(!SGLyricsHasRecentDemand(INFINITY, video));
    assert(!SGLyricsHasRecentDemand(2000, NAN));
    return 0;
}
