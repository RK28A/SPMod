// The moving background behind the mod's settings pages (Appearance → Animated background): one of eleven
// styles drawn in a colour that follows the song playing or the accent. A new colour does not cut in: the
// style finishes the loop it is on, then the same style in the new colour fades in over it.
#import <UIKit/UIKit.h>

#define SGKeyBackdrop @"spotifyglass.animatedbg"
#define SGKeyBackdropStyle @"spotifyglass.animatedbg.style"
#define SGKeyBackdropSource @"spotifyglass.animatedbg.source"   // 0 the song's cover, 1 the accent
#define SGKeyBackdropSongColor @"spotifyglass.animatedbg.songColor"

extern NSNotificationName const SGBackdropDidChangeNotification;   // a setting above changed

NSArray<NSString *> *SGBackdropStyleNames(void);
// Puts the background behind a page's table, or takes it away once the switch is off. Every page of the
// mod's asks as it loads and each time it comes into view (SGPage.m), so one opened before the switch was
// turned follows too.
void SGBackdropSync(UITableView *table);
// The same background behind a page of Spotify's own (Home, the library): placed at the back of `page` from
// the page's layout pass, its own fills above cleared so it shows.
void SGBackdropPlace(UIView *page);
// The fills of `page` and of what covers nearly all of it, three levels down, cleared, so `behind`, a view at
// the back of the page, shows through them. For every layout pass of the page: Spotify fills them again.
void SGBackdropClearFills(UIView *page, UIView *behind);
// The colour the background is drawn in under Follows the song, from a higher layer: the redesign hands its
// accent, so the background and the tab bar are one colour from one source; the native look hands the
// cover's (Shared/Player/SongColor.x). Main thread.
void SGBackdropSetSongColor(UIColor *color);
// The music, from a higher layer: whether a song plays, and each beat as Vibrations feels it. Without the
// latter a steady step stands in while a song plays. Main thread.
void SGBackdropSetPlaying(BOOL playing);
void SGBackdropBeat(float intensity);

// Each style's own settings (Appearance → Customise this style), kept per style: how fast it runs (1 is its
// own pace), how bright it is, how far its colours stray from the one it is given (1 is the widest), and how
// hard it answers the music (0 not at all; under 1 it lets beats pass, over 1 it answers harder and throws
// more). A change reaches the backgrounds on screen a moment after the last one.
typedef NS_ENUM(NSInteger, SGBackdropTune) { SGBackdropTuneSpeed, SGBackdropTuneGlow, SGBackdropTuneSpread, SGBackdropTuneMusic };
double SGBackdropTuneValue(SGBackdropTune what, NSInteger style);
void SGBackdropSetTune(SGBackdropTune what, NSInteger style, double value);
void SGBackdropResetTune(NSInteger style);
// How often the background is drawn: 0 thirty times a second (the default, the coolest), 1 sixty, 2 as often
// as the screen allows.
#define SGKeyBackdropRate @"spotifyglass.animatedbg.rate"
