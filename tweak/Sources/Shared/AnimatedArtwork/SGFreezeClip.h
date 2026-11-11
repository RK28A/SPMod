#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// What holding the lock screen's moving artwork on a frame is made of (LockScreenFreeze.h). The system
// plays the clip it is handed and takes no pause or seek, so a hold is a clip of one frame, and going on
// from it is the same clip turned round to start where it was held. Off the main thread, all three.

// The frame of `file` at `at` seconds, stood up the way the clip is shown, and the clip's length. `at` past
// the end wraps, as the loop does; `where` is given where it landed. NULL when the clip cannot be read.
CGImageRef SGFreezeClipFrame(NSURL *file, double at, double *length, double *where) CF_RETURNS_RETAINED;

// A two second clip of `frame` alone, the frame's own size.
BOOL SGFreezeClipWriteStill(NSURL *file, CGImageRef frame);

// `clip` from `from` seconds to its end and then from its start to `from`: the same loop, begun there.
BOOL SGFreezeClipWriteFrom(NSURL *clip, double from, NSURL *file);
