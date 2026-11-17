#import <UIKit/UIKit.h>

// Opening a page from the profile menu: Spotify closes the menu onto Home, then pushes the page, so Home
// showed between the two. A veil in the page's own background covers the screen from the tap, the page is
// pushed under it, and the veil goes in the chosen style, so the menu goes straight to the page.
#define SGKeyPageTransition @"spotifyglass.transition.style"
typedef NS_ENUM(NSInteger, SGPageTransitionStyle) {
    SGPageTransitionOff = 0,   // Spotify's own: Home shows between
    SGPageTransitionFade,
    SGPageTransitionZoom,      // the default
    SGPageTransitionRise,
    SGPageTransitionBlur,
    SGPageTransitionCircle,
    SGPageTransitionCurtain,
    SGPageTransitionGlass,
};
NSArray<NSString *> *SGPageTransitionNames(void);
NSArray<NSString *> *SGPageTransitionNotes(void);

// The veil up from `point` (in the window), until a new page is on top of the stack, then away. Main thread.
void SGPageVeilUp(CGPoint point);
// Whether a veil is up now (the transition is not Off).
BOOL SGPageVeilIsUp(void);
// The page is in under the veil: it goes away now instead of waiting for the stack to change.
void SGPageVeilReady(void);
