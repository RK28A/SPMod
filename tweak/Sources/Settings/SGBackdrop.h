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
// The playing song's colour, from a higher layer (Shared/Player/SongColor.x). Main thread.
void SGBackdropSetSongColor(UIColor *color);
