// The colour of the song playing, for the settings' moving background (Settings/SGBackdrop.h) under either
// look: the most vivid part of the cover Spotify hands the system. Spotify names a track before it has its
// cover, so the now playing info is looked at a few times after a track comes in, until the artwork it
// carries is a new one under that track's title.
#import <MediaPlayer/MediaPlayer.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Settings/SGBackdrop.h"
#import "NowPlayingExtras.h"
#import "PlayerState.h"

static const int kLooks = 12;
enum { kGrid = 8 };
static const NSTimeInterval kLookEvery = 0.5;

@interface SGSongColorWatcher : NSObject <SGPlayerStateObserver>
@end

static SGSongColorWatcher *sg_watcher;
static NSString *sg_title;
static MPMediaItemArtwork *sg_read;
static NSUInteger sg_turn;

static UIColor *vividColor(CGImageRef pixels) {
    uint8_t grid[kGrid * kGrid * 4];
    memset(grid, 0, sizeof(grid));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = space ? CGBitmapContextCreate(grid, kGrid, kGrid, 8, kGrid * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) return nil;
    CGContextSetInterpolationQuality(context, kCGInterpolationMedium);
    CGContextDrawImage(context, CGRectMake(0, 0, kGrid, kGrid), pixels);
    CGContextRelease(context);
    CGFloat best = -1, hue = 0, saturation = 0;
    for (int i = 0; i < kGrid * kGrid; i++) {
        CGFloat r = grid[i * 4] / 255.0, g = grid[i * 4 + 1] / 255.0, b = grid[i * 4 + 2] / 255.0;
        CGFloat h = 0, s = 0, v = 0, a = 0;
        [[UIColor colorWithRed:r green:g blue:b alpha:1] getHue:&h saturation:&s brightness:&v alpha:&a];
        CGFloat score = s * (0.4 + 0.6 * v);
        if (score <= best) continue;
        best = score;
        hue = h;
        saturation = s;
    }
    // A cover with no colour in it gives a quiet grey blue rather than a hue read out of noise.
    if (best < 0.1) return [UIColor colorWithHue:0.6 saturation:0.12 brightness:0.8 alpha:1];
    return [UIColor colorWithHue:hue saturation:MIN(0.85, MAX(0.5, saturation)) brightness:0.92 alpha:1];
}

static void look(NSUInteger turn, int left) {
    if (turn != sg_turn || left <= 0) return;
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    MPMediaItemArtwork *artwork = info[MPMediaItemPropertyArtwork];
    if ([artwork isKindOfClass:MPMediaItemArtwork.class] && artwork != sg_read && SGNowPlayingTitlesMatch(info[MPMediaItemPropertyTitle], sg_title)) {
        CGImageRef pixels = [artwork imageWithSize:CGSizeMake(64, 64)].CGImage;
        UIColor *color = pixels ? vividColor(pixels) : nil;
        if (color) {
            sg_read = artwork;
            SGBackdropSetSongColor(color);
            return;
        }
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLookEvery * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        look(turn, left - 1);
    });
}

@implementation SGSongColorWatcher

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSString *title = state.track.trackTitle;
    if (!title.length || [title isEqualToString:sg_title]) return;
    sg_title = [title copy];
    NSUInteger turn = ++sg_turn;
    if (!SGHidden(SGKeyBackdrop) || SGInt(SGKeyBackdropSource, 0) != 0) return;
    look(turn, kLooks);
}

@end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        sg_watcher = [SGSongColorWatcher new];
        SGAddPlayerStateObserver(sg_watcher);
    });
}
