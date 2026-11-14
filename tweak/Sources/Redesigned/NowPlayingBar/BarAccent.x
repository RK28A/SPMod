#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "NowPlayingBar.h"

static void tintConnect(UIView *bar) {
    if (!bar) return;
    SGForEachView(bar, ^(UIView *host) {
        NSString *name = NSStringFromClass(host.class);
        if ([name containsString:@"ConnectStateView"] || [name containsString:@"ConnectButtonView"]) SGRAccentRetint(host);
    });
}

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    SGDebugOnce(@"hook Redesigned/NowPlayingBar/BarAccent.x: -[NowPlayingBarViewController viewDidLayoutSubviews] first call");
    %orig;
    tintConnect(((UIViewController *)self).view);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/NowPlayingBar/BarAccent.x on");
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        tintConnect(sgr_nowPlayingRoot);
    }];
}
