// LockScreenFreeze.h says what this is and why the frame it holds is reckoned, not read.
//
// Everything but the clip making runs on the main thread. A pause or a play counts a turn and an offer
// counts an offer: clip making that ends after a newer one of either is dropped, so a quick pause and play
// leaves the lock screen as it was.
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "AnimatedArtwork.h"
#import "LockScreenFreeze.h"
#import "SGFreezeClip.h"

// The held and turned clips kept, newest first: the one the system is playing is among them.
static const NSUInteger kKept = 6;
// Held this near its start, a clip goes on from its start: turning it round would change nothing seen.
static const double kNearStart = 0.15;

@interface SGLockFreezeWatcher : NSObject <SGPlayerStateObserver>
@end

static SGLockFreezeWatcher *sg_watcher;
static dispatch_queue_t sg_queue;
static NSString *sg_key, *sg_title;
static NSString *sg_name;     // the clip as LockScreenMotion.x offered it
static NSString *sg_turned;   // the turned clip offered after a hold, nil while the first plays
static void (^sg_clip)(void (^)(NSURL *));
static void (^sg_again)(void);
static NSUInteger sg_offer, sg_turn;
static double sg_origin;        // where in the clip the file the system holds starts
static double sg_played;        // seconds it has played since the system took it, up to sg_since
static CFTimeInterval sg_since; // when it last began to play, 0 while the song is paused
static BOOL sg_paused, sg_held;
static double sg_heldAt;
static NSURL *sg_heldClip;

static NSURL *folder(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *url = [caches URLByAppendingPathComponent:@"spoti.pw/MotionHold" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

// Apart from the downloads (SGMotionStore.m), whose newest few a pause must not push out.
static void trim(void) {
    NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder()
        includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    if (files.count <= kKept) return;
    NSArray<NSURL *> *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *left = nil, *right = nil;
        [a getResourceValue:&left forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&right forKey:NSURLContentModificationDateKey error:nil];
        return [left ?: NSDate.distantPast compare:right ?: NSDate.distantPast];
    }];
    for (NSUInteger i = 0; i + kKept < oldestFirst.count; i++) [NSFileManager.defaultManager removeItemAtURL:oldestFirst[i] error:nil];
}

static NSURL *madeFile(NSString *kind, NSURL *clip, double where) {
    NSString *name = [NSString stringWithFormat:@"%@-%@-%06ld.mp4", kind, clip.lastPathComponent.stringByDeletingPathExtension,
                      (long)lround(where * 1000)];
    return [folder() URLByAppendingPathComponent:name];
}

// `image` filled into `size` about its middle, as the preview the system asks for.
static UIImage *fitted(UIImage *image, CGSize size) {
    size = CGSizeMake(round(size.width), round(size.height));
    if (!image || size.width < 1 || size.height < 1 || image.size.width <= 0 || image.size.height <= 0) return image;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 1;
    format.opaque = YES;
    CGFloat scale = MAX(size.width / image.size.width, size.height / image.size.height);
    CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [image drawInRect:CGRectMake((size.width - drawn.width) / 2, (size.height - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

static double position(void) {
    return sg_origin + sg_played + (sg_since > 0 ? CACurrentMediaTime() - sg_since : 0);
}

// `counts`: the clip plays on, so the clock starts again as the system takes it; a held frame's does not.
API_AVAILABLE(ios(26.0))
static void offer(NSString *key, NSString *title, NSURL *file, UIImage *preview, BOOL counts) {
    NSString *name = file.lastPathComponent;
    MPMediaItemAnimatedArtwork *artwork = [[MPMediaItemAnimatedArtwork alloc] initWithArtworkID:name
        previewImageRequestHandler:^(CGSize wanted, void (^completion)(UIImage *)) { completion(fitted(preview, wanted)); }
        videoAssetFileURLRequestHandler:^(CGSize wanted, void (^completion)(NSURL *)) {
            completion(file);
            if (counts) SGLockFreezeHandedOver(name);
        }];
    SGNowPlayingSetExtras(@"motion", @{key: artwork}, title);
}

static void startOver(void) {
    sg_origin = 0;
    sg_played = 0;
    sg_since = sg_paused ? 0 : CACurrentMediaTime();
    sg_turned = nil;
    if (sg_again) sg_again();
}

API_AVAILABLE(ios(26.0))
static void hold(void) {
    if (!sg_clip || !sg_key) SGLog(@"lock hold: paused with no moving artwork offered (the Lyrics view and iOS's own artwork are not held)");
    if (!sg_clip || !sg_key || sg_held) return;
    NSUInteger offered = sg_offer, turn = ++sg_turn;
    double at = position();
    NSString *key = sg_key, *title = sg_title;
    SGLog(@"lock hold: paused %.1f s into %@, holding", at, sg_name);
    sg_clip(^(NSURL *file) {
        dispatch_async(sg_queue, ^{
            if (!file) SGLog(@"lock hold: the clip could not be made, nothing held");
            if (!file) return;
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            double length = 0, where = 0;
            CGImageRef frame = SGFreezeClipFrame(file, at, &length, &where);
            NSURL *still = frame ? madeFile(@"held", file, where) : nil;
            BOOL ok = NO;
            if (still) {
                trim();
                ok = [NSFileManager.defaultManager fileExistsAtPath:still.path] || SGFreezeClipWriteStill(still, frame);
            }
            UIImage *preview = frame ? [UIImage imageWithCGImage:frame] : nil;
            if (frame) CGImageRelease(frame);
            SGLog(@"lock hold: %@ held at %.2f of %.2f s (%.1f s played) %@ in %.0f ms", file.lastPathComponent, where, length, at,
                  ok ? @"ready" : @"not made", (CFAbsoluteTimeGetCurrent() - start) * 1000);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!ok || offered != sg_offer || turn != sg_turn) return;
                sg_held = YES;
                sg_heldAt = where;
                sg_heldClip = file;
                offer(key, title, still, preview, NO);
                // Turned round while the song is held, so playing again finds it made.
                if (where <= kNearStart) return;
                dispatch_async(sg_queue, ^{
                    NSURL *turned = madeFile(@"from", file, where);
                    if ([NSFileManager.defaultManager fileExistsAtPath:turned.path]) return;
                    trim();
                    SGFreezeClipWriteFrom(file, where, turned);
                });
            });
        });
    });
}

API_AVAILABLE(ios(26.0))
static void goOn(void) {
    NSUInteger offered = sg_offer, turn = ++sg_turn;
    if (!sg_held) return;
    sg_held = NO;
    NSURL *file = sg_heldClip;
    double where = sg_heldAt;
    NSString *key = sg_key, *title = sg_title;
    if (!file || !key || where <= kNearStart) {
        startOver();
        return;
    }
    dispatch_async(sg_queue, ^{
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        NSURL *turned = madeFile(@"from", file, where);
        BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:turned.path];
        if (!ok) {
            trim();
            ok = SGFreezeClipWriteFrom(file, where, turned);
        }
        CGImageRef frame = ok ? SGFreezeClipFrame(turned, 0, NULL, NULL) : NULL;
        UIImage *preview = frame ? [UIImage imageWithCGImage:frame] : nil;
        if (frame) CGImageRelease(frame);
        SGLog(@"lock hold: %@ from %.2f s %@ in %.0f ms", file.lastPathComponent, where, ok && preview ? @"ready" : @"not made, the clip starts over",
              (CFAbsoluteTimeGetCurrent() - start) * 1000);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (offered != sg_offer || turn != sg_turn) return;
            if (!ok || !preview) {
                startOver();
                return;
            }
            sg_origin = where;
            sg_played = 0;
            sg_since = sg_paused ? 0 : CACurrentMediaTime();
            sg_turned = turned.lastPathComponent;
            offer(key, title, turned, preview, YES);
        });
    });
}

@implementation SGLockFreezeWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    BOOL paused = state.isPaused;
    if (paused == sg_paused) return;
    sg_paused = paused;
    if (paused) {
        if (sg_since > 0) sg_played += CACurrentMediaTime() - sg_since;
        sg_since = 0;
        if (@available(iOS 26.0, *)) {
            if (SGEnabled(SGKeyLockScreenPauseMotion)) hold();
        }
    } else {
        sg_since = CACurrentMediaTime();
        // A frame held before the switch went off still goes on.
        if (@available(iOS 26.0, *)) goOn();
    }
}

@end

static void setUp(void) {
    if (sg_watcher) return;
    sg_queue = dispatch_queue_create("spotifyglass.lockscreen.hold", DISPATCH_QUEUE_SERIAL);
    sg_watcher = [SGLockFreezeWatcher new];
    sg_paused = SGPlayerState().isPaused;
    SGAddPlayerStateObserver(sg_watcher);
}

void SGLockFreezeOffered(NSString *key, NSString *title, NSString *name,
                         void (^clip)(void (^done)(NSURL *file)), void (^again)(void)) {
    setUp();
    sg_offer++;
    sg_turn++;
    sg_key = [key copy];
    sg_title = [title copy];
    sg_name = [name copy];
    sg_clip = [clip copy];
    sg_again = [again copy];
    sg_turned = nil;
    sg_origin = 0;
    sg_played = 0;
    sg_since = sg_paused ? 0 : CACurrentMediaTime();
    sg_held = NO;
    sg_heldClip = nil;
    // A track that comes in paused is held on its first frame, as it would be had it been paused there.
    if (@available(iOS 26.0, *)) {
        if (sg_paused && SGEnabled(SGKeyLockScreenPauseMotion)) hold();
    }
}

void SGLockFreezeHandedOver(NSString *name) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL first = [name isEqualToString:sg_name];
        if (!first && ![name isEqualToString:sg_turned]) return;
        if (first) sg_origin = 0;
        sg_played = 0;
        sg_since = sg_paused ? 0 : CACurrentMediaTime();
    });
}

void SGLockFreezeCleared(void) {
    sg_offer++;
    sg_turn++;
    sg_key = nil;
    sg_title = nil;
    sg_name = nil;
    sg_turned = nil;
    sg_clip = nil;
    sg_again = nil;
    sg_held = NO;
    sg_heldClip = nil;
    sg_since = 0;
    sg_played = 0;
    sg_origin = 0;
}

SGModRow *SGLockFreezeRow(void) {
    SGModRow *row = SGSwitchRow(@"Pause animation with playback",
        @"Experimental. Holds the moving artwork on a frame while the song is paused, then goes on from it. iOS gives no clock for its player, so the frame is an estimate",
        SGKeyLockScreenPauseMotion);
    row.visible = ^BOOL {
        NSArray<NSString *> *views = SGLockScreenAvailableStarViews();
        return [views containsObject:@"canvas"] || [views containsObject:@"fill"] || [views containsObject:@"colorful"];
    };
    return row;
}
