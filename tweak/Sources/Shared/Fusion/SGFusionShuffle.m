// Fusion Shuffle (Fusion.h). The pool is every track of the library's playlists that are not excluded and
// whose items Spotify gives, followed ones too where its own endpoints answer; a track only an excluded
// playlist holds is never in it, and one an allowed playlist holds too is. The order is drawn once, the first track is started as a context of its own and the
// next few are put in Spotify's queue, topped up as they play, so skip, back and the queue work as ever.
// Playing something else ends it. The calls into the player are the ones Local Jam makes, behind the same
// guards: a player that refuses is said so, not crashed into.
#import <objc/message.h>
#import <objc/runtime.h>
#import "Fusion.h"
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Player/PlayerState.h"

NSNotificationName const SGFusionShuffleDidChangeNotification = @"SGFusionShuffleDidChangeNotification";

static NSString *const kRecentKey = @"spotifyglass.fusion.recent";
static const NSUInteger kAhead = 12, kLongestOrder = 500;
static const NSTimeInterval kLibraryKeptFor = 30 * 60;
// Tracks in a row from outside the order before it is taken that the listener moved on.
static const int kStrayLimit = 2;

@interface SGFusionWatcher : NSObject <SGPlayerStateObserver>
@end

static SGFusionWatcher *sg_watcher;
static BOOL sg_active, sg_loading;
static NSString *sg_status = @"Off";
static NSArray<NSString *> *sg_order;
static NSUInteger sg_queued;
static NSString *sg_lastURI;
static int sg_stray;
// The library as last read: a list of tracks per playlist id.
static NSDictionary<NSString *, NSArray<SGFusionItem *> *> *sg_library;
static NSArray<NSString *> *sg_skippedPlaylists;
static CFAbsoluteTime sg_libraryRead;

static void say(NSString *status) {
    if (![status hasPrefix:@"Reading"]) SGLog(@"fusion shuffle: %@", status);
    sg_status = [status copy];
    [NSNotificationCenter.defaultCenter postNotificationName:SGFusionShuffleDidChangeNotification object:nil];
}

BOOL SGFusionShuffleActive(void) { return sg_active || sg_loading; }
NSString *SGFusionShuffleStatus(void) { return sg_status; }

void SGFusionShuffleForgetLibrary(void) {
    sg_library = nil;
    sg_libraryRead = 0;
}

static NSString *uriOf(SPTPlayerTrack *track) {
    id uri = track.URI;
    if ([uri isKindOfClass:NSURL.class]) return [(NSURL *)uri absoluteString];
    return [uri isKindOfClass:NSString.class] ? uri : nil;
}

static BOOL enqueue(NSString *uri) {
    id player = SGPlaybackPlayer();
    Class trackClass = NSClassFromString(@"SPTPlayerTrack");
    SEL make = NSSelectorFromString(@"trackWithURI:"), add = NSSelectorFromString(@"addToQueue:");
    NSURL *url = [NSURL URLWithString:uri];
    if (!player || !url || ![trackClass respondsToSelector:make] || ![player respondsToSelector:add]) return NO;
    @try {
        id track = ((id (*)(id, SEL, id))objc_msgSend)(trackClass, make, url);
        if (!track) return NO;
        ((id (*)(id, SEL, id))objc_msgSend)(player, add, track);
        return YES;
    } @catch (NSException *exception) {
        SGLog(@"fusion shuffle: the queue refused %@: %@", uri, exception.reason);
        return NO;
    }
}

static BOOL start(NSString *uri) {
    id player = SGPlaybackPlayer();
    Class contextClass = NSClassFromString(@"ESPContext");
    SEL play = NSSelectorFromString(@"playContext:options:loggingParams:origin:"), setURI = NSSelectorFromString(@"setUri:");
    if (!player || !contextClass || ![player respondsToSelector:play]) {
        SGLog(@"fusion shuffle: cannot start, player %@, ESPContext %@, playContext %@", player ? NSStringFromClass([player class]) : @"not found yet",
              contextClass ? @"found" : @"missing", [player respondsToSelector:play] ? @"answered" : @"not answered");
        return NO;
    }
    NSObject *context = [[contextClass alloc] init];
    if (![context respondsToSelector:setURI]) {
        SGLog(@"fusion shuffle: cannot start, ESPContext takes no setUri:");
        return NO;
    }
    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(context, setURI, uri);
        ((id (*)(id, SEL, id, id, id, id))objc_msgSend)(player, play, context, nil, nil, nil);
        return YES;
    } @catch (NSException *exception) {
        SGLog(@"fusion shuffle: the player refused %@: %@", uri, exception.reason);
        return NO;
    }
}

static void remember(NSString *uri) {
    NSInteger window = MAX(0, SGInt(SGKeyFusionRecentWindow, 20));
    NSMutableArray<NSString *> *recent = [[NSUserDefaults.standardUserDefaults stringArrayForKey:kRecentKey] mutableCopy] ?: [NSMutableArray array];
    [recent removeObject:uri];
    [recent addObject:uri];
    while ((NSInteger)recent.count > MAX(window, 1)) [recent removeObjectAtIndex:0];
    [NSUserDefaults.standardUserDefaults setObject:recent forKey:kRecentKey];
}

static void topUp(NSUInteger playing) {
    while (sg_queued < sg_order.count && sg_queued <= playing + kAhead) {
        if (!enqueue(sg_order[sg_queued])) break;
        sg_queued++;
    }
}

// The order: the allowed playlists' tracks, each once when asked, the explicit ones out when asked, the ones
// heard lately out while enough are left, then drawn a track at a time or a playlist at a time.
static NSArray<NSString *> *draw(void) {
    NSSet<NSString *> *excluded = [NSSet setWithArray:[NSUserDefaults.standardUserDefaults stringArrayForKey:SGKeyFusionExcluded] ?: @[]];
    BOOL dedupe = SGEnabled(SGKeyFusionDedupe), allowExplicit = SGEnabled(SGKeyFusionExplicit);
    NSSet<NSString *> *recent = SGEnabled(SGKeyFusionAvoidRecent)
        ? [NSSet setWithArray:[NSUserDefaults.standardUserDefaults stringArrayForKey:kRecentKey] ?: @[]] : [NSSet set];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    NSMutableArray<NSMutableArray<NSString *> *> *lists = [NSMutableArray array];
    NSMutableArray<NSString *> *held = [NSMutableArray array];
    NSUInteger count = 0;
    for (NSString *playlist in sg_library) {
        if ([excluded containsObject:playlist]) continue;
        NSMutableArray<NSString *> *list = [NSMutableArray array];
        for (SGFusionItem *item in sg_library[playlist]) {
            if (!item.isTrack || (!allowExplicit && item.isExplicit)) continue;
            if (dedupe && [seen containsObject:item.uri]) continue;
            [seen addObject:item.uri];
            if ([recent containsObject:item.uri]) [held addObject:item.uri];
            else [list addObject:item.uri];
        }
        if (list.count) [lists addObject:list];
        count += list.count;
    }
    // Too few left once the ones heard lately are out: they come back in rather than the mix running dry.
    if (count < 10 && held.count) {
        [lists addObject:held];
        count += held.count;
    }
    NSMutableArray<NSString *> *order = [NSMutableArray array];
    if (SGInt(SGKeyFusionSampling, 0) == 1) {
        for (NSMutableArray<NSString *> *list in lists) {
            for (NSUInteger i = list.count; i > 1; i--) [list exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        }
        while (lists.count && order.count < kLongestOrder) {
            NSUInteger pick = arc4random_uniform((uint32_t)lists.count);
            NSMutableArray<NSString *> *list = lists[pick];
            [order addObject:list.lastObject];
            [list removeLastObject];
            if (!list.count) [lists removeObjectAtIndex:pick];
        }
    } else {
        for (NSMutableArray<NSString *> *list in lists) [order addObjectsFromArray:list];
        for (NSUInteger i = order.count; i > 1; i--) [order exchangeObjectAtIndex:i - 1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        if (order.count > kLongestOrder) [order removeObjectsInRange:NSMakeRange(kLongestOrder, order.count - kLongestOrder)];
    }
    return order;
}

static void play(void) {
    sg_loading = NO;
    NSArray<NSString *> *order = draw();
    if (!order.count) {
        sg_active = NO;
        say(@"No track to play: every playlist is excluded, empty, or not readable");
        return;
    }
    // A song already playing is left to play: the mix is queued behind it. With nothing playing it starts.
    SPTPlayerState *state = SGPlayerState();
    NSString *playing = state.track && !state.isPaused ? uriOf(state.track) : nil;
    if (playing.length) {
        sg_order = order;
        sg_queued = 0;
        sg_lastURI = playing;
    } else {
        if (!start(order.firstObject)) {
            sg_active = NO;
            say(@"Spotify's player refused to start the mix");
            return;
        }
        sg_order = order;
        sg_queued = 1;
        sg_lastURI = order.firstObject;
        remember(order.firstObject);
    }
    sg_stray = 0;
    sg_active = YES;
    topUp(0);
    if (!sg_queued) {
        sg_active = NO;
        sg_order = nil;
        say(@"Spotify's queue refused the mix");
        return;
    }
    NSString *skipped = sg_skippedPlaylists.count ? [NSString stringWithFormat:@" · %lu not readable", (unsigned long)sg_skippedPlaylists.count] : @"";
    say([NSString stringWithFormat:@"On · %lu tracks mixed%@", (unsigned long)order.count, skipped]);
    SGLog(@"fusion shuffle: %lu tracks, %lu queued, not readable: %@", (unsigned long)order.count, (unsigned long)sg_queued,
          [sg_skippedPlaylists componentsJoinedByString:@", "]);
}

static void readNext(NSArray<SGFusionPlaylist *> *playlists, NSUInteger index, NSMutableDictionary *library, NSMutableArray<NSString *> *skipped) {
    if (!sg_loading) return;
    if (index >= playlists.count) {
        sg_library = library;
        sg_skippedPlaylists = skipped;
        sg_libraryRead = CFAbsoluteTimeGetCurrent();
        play();
        return;
    }
    SGFusionPlaylist *playlist = playlists[index];
    NSSet<NSString *> *excluded = [NSSet setWithArray:[NSUserDefaults.standardUserDefaults stringArrayForKey:SGKeyFusionExcluded] ?: @[]];
    // An excluded playlist is not even read.
    if ([excluded containsObject:playlist.identifier]) {
        readNext(playlists, index + 1, library, skipped);
        return;
    }
    say([NSString stringWithFormat:@"Reading the library… %lu of %lu playlists", (unsigned long)index + 1, (unsigned long)playlists.count]);
    SGFusionLoadItems(playlist.identifier, ^(NSArray<SGFusionItem *> *items, NSInteger unreadable, NSString *error) {
        if (items) library[playlist.identifier] = items;
        else [skipped addObject:playlist.name];
        readNext(playlists, index + 1, library, skipped);
    });
}

@implementation SGFusionWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!sg_active) return;
    NSString *uri = uriOf(state.track);
    if (!uri.length || [uri isEqualToString:sg_lastURI]) return;
    sg_lastURI = uri;
    NSUInteger index = [sg_order indexOfObject:uri];
    if (index == NSNotFound) {
        if (++sg_stray < kStrayLimit) return;
        sg_active = NO;
        say(@"Off");
        SGLog(@"fusion shuffle: something else is playing, off");
        return;
    }
    sg_stray = 0;
    remember(uri);
    topUp(index);
}

@end

void SGFusionShuffleStart(void) {
    if (sg_loading) return;
    if (!sg_watcher) {
        sg_watcher = [SGFusionWatcher new];
        SGAddPlayerStateObserver(sg_watcher);
    }
    sg_active = NO;
    sg_loading = YES;
    if (sg_library && CFAbsoluteTimeGetCurrent() - sg_libraryRead < kLibraryKeptFor) {
        play();
        return;
    }
    say(@"Reading the library…");
    SGFusionLoadPlaylists(^(NSArray<SGFusionPlaylist *> *playlists, NSString *error) {
        if (!sg_loading) return;
        if (!playlists) {
            sg_loading = NO;
            say(error ?: @"The library could not be read");
            return;
        }
        readNext(playlists, 0, [NSMutableDictionary dictionary], [NSMutableArray array]);
    });
}

void SGFusionShuffleStop(void) {
    sg_loading = NO;
    sg_active = NO;
    sg_order = nil;
    say(@"Off");
}
