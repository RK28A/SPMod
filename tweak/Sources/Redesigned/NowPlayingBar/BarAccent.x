#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Kit/SGRAccentTint.h"
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
    %orig;
    tintConnect(((UIViewController *)self).view);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        tintConnect(sgr_nowPlayingRoot);
    }];
}
