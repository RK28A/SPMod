#import "Core/SGCore.h"
#import "Shared/Gestures/Gestures.h"

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {
    SGDebugOnce(@"hook Redesigned/Player/PlayerGestures.x: -[CoverArtTiltView handleTap] first call");
    if (SGFlag(SGKeyGestures, NO)) return;
    %orig;
}
%end

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    SGDebugOnce(@"hook Redesigned/Player/PlayerGestures.x: -[AccessibleCollectionView layoutSubviews] first call");
    %orig;
    SGGestureAttach((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/Player/PlayerGestures.x on");
    %init;
    SGRequireClasses(@[
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
    ]);
}
