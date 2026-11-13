#import <UIKit/UIKit.h>

// Interface animations (Appearance): 0 off, 1 subtle, 2 lively. Read as each row comes in, so it applies at once.
#define SGRKeyEntrance @"spotifyglass.redesign.entrance"

// A row of a list coming on screen fades in and settles into its place; the rows of a page that has just
// opened come one after another from the top. Called on every layout pass of the row: a row is new when it
// has not been seen, or is no longer where it was (reused for another place). Main thread.
void SGREntrance(UIView *row, UIScrollView *list);
