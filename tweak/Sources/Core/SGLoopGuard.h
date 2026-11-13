#import <Foundation/Foundation.h>

// YES when the mod's pass named `name` has run more than 400 times since the main run loop last turned: a
// layout pass going round with Spotify's for ever inside one frame. The caller then does nothing for the rest
// of that turn. Logged once a name, with the count. Main thread only.
BOOL SGLoopGuard(const char *name);
// What the mod changed during this turn, by name: listed with their counts when a guard trips, so the log
// says which change the page kept laying out again on.
void SGLoopNote(const char *what);
