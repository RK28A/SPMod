// Playlist Fusion and Fusion Shuffle (Mod Settings → Player → Playlist Fusion), either look.
//
// Playlist Fusion copies the items of the playlists picked as sources (red) onto the end of one destination
// (green), in order, and only once every copied item is read back from the destination may it take the
// sources out of the library. Spotify has no call that deletes a playlist: taking one out of the library
// is unfollowing it, and it stays for whoever else follows it.
//
// Fusion Shuffle plays the tracks of every playlist in the library that is not excluded, mixed. No playlist
// is made or changed: one track is started and the rest go into Spotify's own queue a few at a time.
//
// Both talk to Spotify's Web API as the signed-in app (SGFusionAPI.m). The API only gives the items of
// playlists the user owns or collaborates on; the others are passed over and named.
#import <UIKit/UIKit.h>

#define SGKeyFusionExcluded @"spotifyglass.fusion.excluded"          // playlist ids Fusion Shuffle never draws from
#define SGKeyFusionDedupe @"spotifyglass.fusion.dedupe"              // on unless switched off
#define SGKeyFusionSampling @"spotifyglass.fusion.sampling"          // 0 a chance per track, 1 a chance per playlist
#define SGKeyFusionAvoidRecent @"spotifyglass.fusion.avoidRecent"    // on unless switched off
#define SGKeyFusionRecentWindow @"spotifyglass.fusion.recentWindow"
#define SGKeyFusionExplicit @"spotifyglass.fusion.explicit"          // on unless switched off
#define SGKeyFusionDuplicates @"spotifyglass.fusion.duplicates"      // 0 every entry kept, 1 the destination's skipped
#define SGKeyFusionKeepSources @"spotifyglass.fusion.keepSources"    // on unless switched off: copy only

extern NSNotificationName const SGFusionShuffleDidChangeNotification;

@interface SGFusionPlaylist : NSObject
@property (nonatomic, copy) NSString *identifier, *name, *owner;
@property (nonatomic) NSInteger total;
@property (nonatomic) BOOL editable;   // the user's own or collaborative: its items can be read and added to
@end

@interface SGFusionItem : NSObject
@property (nonatomic, copy) NSString *uri;
@property (nonatomic) BOOL isExplicit, isTrack;
@end

// Every call answers on the main queue; `error` is a line to show, nil when it went through.
void SGFusionLoadPlaylists(void (^done)(NSArray<SGFusionPlaylist *> *playlists, NSString *error));
void SGFusionLoadItems(NSString *playlist, void (^done)(NSArray<SGFusionItem *> *items, NSInteger unreadable, NSString *error));
// `from` is where to go on from in `uris`, for a second try; `added` says how far it got.
void SGFusionAddItems(NSString *playlist, NSArray<NSString *> *uris, NSUInteger from,
                      void (^progress)(NSUInteger added), void (^done)(NSUInteger added, NSString *error));
void SGFusionRemoveFromLibrary(NSString *playlist, void (^done)(NSString *error));

BOOL SGFusionShuffleActive(void);
NSString *SGFusionShuffleStatus(void);
void SGFusionShuffleStart(void);
void SGFusionShuffleStop(void);
void SGFusionShuffleForgetLibrary(void);

UIViewController *SGFusionSettingsPage(void);
// The list where a merge is set up, `destination` already green when it names a playlist of the library.
UIViewController *SGFusionMergePage(NSString *destination);

// The library's playlists by name, as last read, for telling a playlist's menu by its heading: the id of the
// one called `name`, nil when none or more than one is. Kept across launches; SGFusionWarmNames reads the
// library once a launch and calls back when the names are there.
NSString *SGFusionPlaylistNamed(NSString *name);
void SGFusionWarmNames(void (^done)(void));
// `button` is one of Spotify's shuffle buttons or a stand-in for one. A long press on it opens the sheet of
// shuffle modes (No Shuffle, Shuffle, Smart Shuffle, Fusion Shuffle); a tap goes on to Fusion Shuffle after
// Spotify's own modes and from it back to none; while Fusion Shuffle is on its glyph covers the button's.
// Called on the button's layout passes: the first call attaches, the others keep the glyph right.
void SGFusionAttachShuffleMenu(UIView *button);
// The colour what is chosen is drawn in, from the look (the redesign's accent); Spotify's green when unset.
extern UIColor *(^SGFusionAccent)(void);

// The shuffle modes, in the order the sheet lists them. Which one is on, as far as can be told: Spotify
// says whether it shuffles, not whether its shuffle is the smart one, so Smart is only known when it was
// chosen from the sheet. Setting one goes through `source`, the button the sheet was opened from, for the
// one mode only Spotify's own button reaches.
typedef NS_ENUM(NSInteger, SGFusionMode) { SGFusionModeNone, SGFusionModeShuffle, SGFusionModeSmart, SGFusionModeFusion };
NSInteger SGFusionModeNow(void);
void SGFusionSetMode(NSInteger mode, UIView *source);
void SGFusionShowModes(UIView *source);
void SGFusionOpenSettings(void);
// A stand-in drawn over one of Spotify's shuffle buttons says which it stands for.
void SGFusionAttachShuffleStandIn(UIView *standIn, UIView *real);

typedef NS_ENUM(NSInteger, SGFusionGlyph) { SGFusionGlyphShuffle, SGFusionGlyphNoShuffle, SGFusionGlyphSmart, SGFusionGlyphFusion };
// A template image `side` points square.
UIImage *SGFusionIcon(SGFusionGlyph glyph, CGFloat side);
