#import <Foundation/Foundation.h>

// Runs the sampler until the matching stop, or for `seconds` when that is above 0 (no stop then).
void SGHangSamplerStart(NSString *reason, NSTimeInterval seconds);
void SGHangSamplerStop(void);

// Called from the watchdog's thread, once a stall, when the main thread has not answered for a second: the
// mod's own hooks that could be going round in a loop turn themselves off. At most four.
void SGHangOnStall(void (*breaker)(void));
