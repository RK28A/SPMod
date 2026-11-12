#import <UIKit/UIKit.h>

#define SGRKeyLibraryHideChips @"spotifyglass.redesign.library.hideChips"
// On unless switched off: every row of the library on a card of glass across the page, a little apart.
#define SGRKeyLibraryGlass @"spotifyglass.redesign.library.glass"

BOOL SGRLibraryHideChipsOn(void);
UIViewController *SGRLibrarySettingsPage(void);

// The list of every library page (trees/clean/library/03.txt:25).
extern NSString *const SGRLibraryListIdentifier;

void SGRLibraryClearScrim(UIView *header);
