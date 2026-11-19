// Whether the app is in the background (the phone locked, or another app in front). Kept from UIKit's own
// notifications, so it is a plain read from any thread: a timer asks it on each beat and does nothing there.
#import <Foundation/Foundation.h>

BOOL SGAppInBackground(void);
