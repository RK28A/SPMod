#import <UIKit/UIKit.h>

// Liquid Glass (Appearance → Liquid Glass): which surfaces are glass, the glass's style, and the zoom on lists.
#define SGRKeyGlassStyle @"spotifyglass.redesign.glass.style"            // 0 frosted, 1 clear, 2 tinted
#define SGRKeyGlassZoom @"spotifyglass.redesign.glass.zoom"              // off until switched on
#define SGRKeyGlassZoomAmount @"spotifyglass.redesign.glass.zoomAmount"  // 0.02 to 0.20, 0.08 unless set

// The glass a card is made of, in the chosen style.
UIVisualEffect *SGRGlassEffectNow(void);
NSInteger SGRGlassStyleNow(void);
// The row in the centre of a library's or a playlist's list drawn larger than the rows away from it.
void SGRGlassZoomList(UIScrollView *list);
UIViewController *SGRGlassSettingsPage(void);
