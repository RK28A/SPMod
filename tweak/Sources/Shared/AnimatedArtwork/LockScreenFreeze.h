// The lock screen's moving artwork held while the song is paused (off until switched on, iOS 26).
//
// The system plays the clip it was handed and offers no pause, no seek and no clock, so nothing here
// stops its player. A pause swaps the clip for one of a single frame, the one the clip is reckoned to be
// on, and playing again swaps in the clip turned round to start there (SGFreezeClip.h). Where the clip
// is on is reckoned: a clock of this process's runs while the song plays, from when the system last took
// the clip's file, and where it stands is taken round the clip's length. The system does not say when it
// starts a clip, so the frame held can be off by however long it waited.
//
// LockScreenMotion.x says what it offers and when it takes it off; the rest is here.
#import <Foundation/Foundation.h>

#define SGKeyLockScreenPauseMotion @"spotifyglass.lockscreen.pauseMotion"

// The clip now offered under the now playing key `key` for `title`, by the name it was offered under.
// `clip` gives its file, making it if it is not there yet, and calls back on any thread; `again` offers it
// once more as it was, for when it cannot be turned round. Main thread.
void SGLockFreezeOffered(NSString *key, NSString *title, NSString *name,
                         void (^clip)(void (^done)(NSURL *file)), void (^again)(void));
// The system was handed the file of the clip offered as `name`. Any thread.
void SGLockFreezeHandedOver(NSString *name);
// The clip was taken off: another track, another view. Main thread.
void SGLockFreezeCleared(void);

@class SGModRow;
SGModRow *SGLockFreezeRow(void);
