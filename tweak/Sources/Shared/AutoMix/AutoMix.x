#import "Core/SGCore.h"
#import "AutoMix.h"
#import "Shared/Player/PlayerState.h"

@interface SGAutoMixWatch : NSObject <SGPlayerStateObserver>
@end
@implementation SGAutoMixWatch
- (void)playerStateDidChange:(SPTPlayerState *)state {
    SGAutoMixPlayerStateChanged(state);
}
@end

%hook SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer addPlayerObserver:] first call");
    %orig;
    SGAutoMixPlayerAvailable(self);
}
- (id)playContext:(id)context options:(id)options loggingParams:(id)logging origin:(id)origin {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer playContext:options:loggingParams:origin:] first call");
    SGAutoMixPlayerAvailable(self);
    return %orig(SGAutoMixCopyContext(context), options, logging, origin);
}
- (id)executePlayCommand:(id)context options:(id)options loggingParams:(id)logging origin:(id)origin {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer executePlayCommand:options:loggingParams:origin:] first call");
    SGAutoMixPlayerAvailable(self);
    return %orig(SGAutoMixCopyContext(context), options, logging, origin);
}
- (id)preparePlaybackOfContext:(id)context options:(id)options viewURI:(id)uri playOrigin:(id)origin {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer preparePlaybackOfContext:options:viewURI:playOrigin:] first call");
    return %orig(SGAutoMixCopyContext(context), options, uri, origin);
}
- (id)preparePlaybackOfContext:(id)context options:(id)options viewURI:(id)uri {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer preparePlaybackOfContext:options:viewURI:] first call");
    return %orig(SGAutoMixCopyContext(context), options, uri);
}
- (id)updateWithContext:(id)context {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTEsperantoPlayer updateWithContext:] first call");
    return %orig(SGAutoMixCopyContext(context));
}
%end

%hook ESPContextPlayerClientImpl
- (id)play:(id)request onResponse:(id)response {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[ESPContextPlayerClientImpl play:onResponse:] first call");
    return %orig(SGAutoMixCopyRequest(request, YES), response);
}
- (id)preparePlay:(id)request onResponse:(id)response {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[ESPContextPlayerClientImpl preparePlay:onResponse:] first call");
    return %orig(SGAutoMixCopyRequest(request, NO), response);
}
- (id)updateContext:(id)request onResponse:(id)response {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[ESPContextPlayerClientImpl updateContext:onResponse:] first call");
    return %orig(SGAutoMixCopyRequest(request, NO), response);
}
%end

%hook _TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation
- (id)initWithScheduler:(id)scheduler {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation initWithScheduler:] first call");
    id preferences = %orig;
    SGAutoMixPreferencesAvailable(preferences);
    return preferences;
}
- (BOOL)audioAutomix {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation audioAutomix] first call");
    SGAutoMixPreferencesAvailable(self);
    return %orig;
}
- (BOOL)audioCrossfade {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation audioCrossfade] first call");
    SGAutoMixPreferencesAvailable(self);
    return %orig;
}
- (NSInteger)audioCrossfadeTime {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation audioCrossfadeTime] first call");
    SGAutoMixPreferencesAvailable(self);
    return %orig;
}
- (void)setAudioAutomix:(BOOL)value {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation setAudioAutomix:] first call");
    SGAutoMixPreferenceChanged(self, @"automix", @(value));
    %orig;
    SGAutoMixPreferencesAvailable(self);
}
- (void)setAudioCrossfade:(BOOL)value {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation setAudioCrossfade:] first call");
    SGAutoMixPreferenceChanged(self, @"crossfade", @(value));
    %orig;
    SGAutoMixPreferencesAvailable(self);
}
- (void)setAudioCrossfadeTime:(NSInteger)value {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTPreferencesImplementation setAudioCrossfadeTime:] first call");
    SGAutoMixPreferenceChanged(self, @"time", @(value));
    %orig;
    SGAutoMixPreferencesAvailable(self);
}
%end

%hook SPTRemoteConfigCoreImpl
- (BOOL)setConfigurationProto:(id)configuration bootstrap:(BOOL)bootstrap {
    SGDebugOnce(@"hook Shared/AutoMix/AutoMix.x: -[SPTRemoteConfigCoreImpl setConfigurationProto:bootstrap:] first call");
    return %orig(SGAutoMixConfiguration(configuration), bootstrap);
}
%end

%ctor {
    SGDebug(@"module Shared/AutoMix/AutoMix.x on");
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!SGAutoMixSupportedVersion(version)) return;
    if (SGAutoMixEnabled()) {
        SGFlagForcer force = ^id(NSString *key) {
            return [@[@"ios-feature-settings.automix_enabled", @"ios-feature-settings.crossfade_enabled"] containsObject:key] ? @YES : nil;
        };
        SGRegisterFlagForcer(YES, force, force);
    }
    %init;
    static SGAutoMixWatch *watch;
    watch = [SGAutoMixWatch new];
    SGAddPlayerStateObserver(watch);
    SGRequireClasses(@[@"SPTEsperantoPlayer", @"SPTPlayerContext", @"ESPContextPlayerClientImpl", @"ESPContext", @"SPTRemoteConfigCoreImpl",
        @"_TtC31Preferences_CorePreferencesImpl28SPTPreferencesImplementation"]);
}
