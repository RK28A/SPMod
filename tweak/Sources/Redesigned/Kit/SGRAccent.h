#import <UIKit/UIKit.h>

#define SGRKeyAccent @"spotifyglass.redesign.accent"   // 0xRRGGBB
#define SGRKeyAccentAuto @"spotifyglass.redesign.accent.auto"
#define SGRKeyAccentRecent @"spotifyglass.redesign.accent.recent"
#define SGRKeyPrettierIcons @"spotifyglass.redesign.prettierIcons"
#define SGKeyHideExplicit @"spotifyglass.hideExplicit"

extern NSNotificationName const SGRAccentDidChangeNotification;

UIColor *SGRAccentColor(void);   // nil while Spotify's own green is kept
NSString *SGRAccentLabel(void);  // "#RRGGBB", or the name of Spotify's own
void SGRSetAccent(NSInteger rgb); // 0xRRGGBB or -1 for Spotify's green; stored, and Automatic turned off
void SGRPickAccent(void);        // the system colour picker over the top of the app, stored on the way out

@class SGModRow;
NSArray<SGModRow *> *SGRAppearanceRows(void);   // the accent colour, for the Appearance card

// The accent Spotify's green became the first time it was made, nil before that: what Spotify draws from a
// colour it keeps is still in this one. And whether a small picture is drawn in an accent of before or in
// Spotify's green, so it is to be drawn again in the accent of now.
UIColor *SGRAccentHanded(void);
BOOL SGRAccentPictureIsStale(UIImage *image);
