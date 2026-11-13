#import <UIKit/UIKit.h>

// Liquid Glass (Appearance → Liquid Glass): which surfaces are glass, the glass's style, and the zoom on lists.
#define SGRKeyGlassStyle @"spotifyglass.redesign.glass.style"            // 0 frosted, 1 clear, 2 tinted
#define SGRKeyGlassZoom @"spotifyglass.redesign.glass.zoom"              // off until switched on
#define SGRKeyGlassZoomAmount @"spotifyglass.redesign.glass.zoomAmount"  // 0.02 to 0.20, 0.08 unless set

// How milky the clear glass is: 0 is the bare glass, only its rim and the light it bends; 1 stops just short
// of frosted. 0.5 unless set.
#define SGRKeyGlassClear @"spotifyglass.redesign.glass.clear"
// The side menu's rows each on a card of glass. Off until switched on.
#define SGRKeyDrawerGlass @"spotifyglass.redesign.drawer.glass"

// The glass a card is made of, in the chosen style.
UIVisualEffect *SGRGlassEffectNow(void);
NSInteger SGRGlassStyleNow(void);
// The style and its strength in one number: a card made under another is made again.
NSInteger SGRGlassLookNow(void);
// The row in the centre of a library's or a playlist's list drawn larger than the rows away from it.
void SGRGlassZoomList(UIScrollView *list);
UIViewController *SGRGlassSettingsPage(void);
