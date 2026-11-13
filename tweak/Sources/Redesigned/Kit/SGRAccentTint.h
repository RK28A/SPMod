#import <UIKit/UIKit.h>

// Spotify colours its Connect glyph and device name green while another device plays, with a colour it
// made once: under an accent that changes after launch (Automatic) they kept the one from launch. Every
// glyph and label under `root` that is drawn in a colour, not white or grey, takes the accent as it is now;
// one drawn white or grey is left, so the control still tells its two states apart. Main thread.
void SGRAccentRetint(UIView *root);
// One small picture as it takes a new image: Spotify's green drawn into it becomes the accent at once, not at
// the next pass over its row (a track's download glyph while it downloads).
void SGRAccentRetintGlyph(UIImageView *glyph);
