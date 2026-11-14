#import "Core/SGCore.h"
#import "SGRKaraokeView.h"

static char kKaraokeKey;

%hook _TtC32Lyrics_FullscreenElementPageImpl10LyricsView
- (void)layoutSubviews {
    SGDebugOnce(@"hook Redesigned/Lyrics/KaraokePage.x: -[LyricsView layoutSubviews] first call");
    %orig;
    UIView *host = (UIView *)self;
    SGRKaraokeView *view = objc_getAssociatedObject(host, &kKaraokeKey);
    if (!view) {
        SGLog(@"karaoke: page opened, playing %@", SGKaraokePlayingTrack());
        view = [[SGRKaraokeView alloc] initWithFrame:host.bounds];
        objc_setAssociatedObject(host, &kKaraokeKey, view, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (view.superview == host) [host bringSubviewToFront:view];
    else [host addSubview:view];
    view.frame = host.bounds;
    [view syncSiblings];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/Lyrics/KaraokePage.x on");
    %init;
    SGRequireClasses(@[@"_TtC32Lyrics_FullscreenElementPageImpl10LyricsView"]);
}
