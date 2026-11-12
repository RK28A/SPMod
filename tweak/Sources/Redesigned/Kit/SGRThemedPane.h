#import <UIKit/UIKit.h>

// A glass card behind a row: a pane of the system's glass at `frame` in `row`, under everything the row
// draws, rounded to `radius`. Nil takes it away. Main thread, on the row's layout passes.
void SGRGlassCard(UIView *row, const void *key, CGRect frame, CGFloat radius, BOOL wanted);

// The theme seen through glass behind part of a list: from `top` (in the list's content) down, the accent's
// light or the moving background with a sheet of glass over it. The pane stays the size of the list's
// window on screen, so the background is drawn once at the screen's size; it follows the scroll
// (SGRThemedPaneFollow, from the scroll views' layout pass). A `top` below zero takes it away.
void SGRThemedPane(UIScrollView *list, CGFloat top);
void SGRThemedPaneFollow(UIScrollView *list);
