// Only actual lock-screen requests may start speculative rendering. Publishing an
// artwork descriptor must remain possible without rendering, to bootstrap demand.
#pragma once
#include <stdbool.h>
#include <math.h>

static inline bool SGLyricsHasRecentDemand(double now, double requestedAt) {
    return isfinite(now) && isfinite(requestedAt) && requestedAt > 0
        && now >= requestedAt && now - requestedAt <= 60.0;
}
