#import <UIKit/UIKit.h>

// The accent as a soft light down from the top of a page that has no colour of its own (Home, the library):
// a view at the back of `page`, put there once and kept to the page's size. It follows the accent, fading
// from the colour it had to the new one. With Animated background on, the page gets that instead, whole.
// Called from the page's layout pass.
void SGRAccentWashPlace(UIView *page);
