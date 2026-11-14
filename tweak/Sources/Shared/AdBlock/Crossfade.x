#import "Core/SGCore.h"
#import "AdBlock.h"

@interface _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation : NSObject
- (void)setAudioCrossfade:(BOOL)on;
@end

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (void)setAudioCrossfadeTime:(NSInteger)time {
    SGDebugOnce(@"hook Shared/AdBlock/Crossfade.x: -[SPTPreferencesImplementation setAudioCrossfadeTime:] first call");
    %orig;
    [self setAudioCrossfade:time > 0];
}
%end

%ctor {
    SGDebug(@"module Shared/AdBlock/Crossfade.x on");
    if (!SGFlag(SGKeyFakePremium, YES)) return;
    %init;
    SGRequireClasses(@[@"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
