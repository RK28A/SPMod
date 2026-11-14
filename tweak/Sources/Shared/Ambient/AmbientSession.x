#import "Core/SGLog.h"
#import <AVFoundation/AVFoundation.h>
#import "AmbientSession.h"

// Spotify and Ambient share the process audio session. A song pause must not tear
// down the independent ambient engine. OS interruptions still suspend it normally.
%hook AVAudioSession
- (BOOL)setActive:(BOOL)active error:(NSError **)error {
    SGDebugOnce(@"hook Shared/Ambient/AmbientSession.x: -[AVAudioSession setActive:error:] first call");
    if (self == AVAudioSession.sharedInstance && SGAmbientDeferSessionDeactivation(active, 0)) {
        return YES;
    }
    return %orig;
}

- (BOOL)setActive:(BOOL)active withOptions:(AVAudioSessionSetActiveOptions)options error:(NSError **)error {
    SGDebugOnce(@"hook Shared/Ambient/AmbientSession.x: -[AVAudioSession setActive:withOptions:error:] first call");
    if (self == AVAudioSession.sharedInstance && SGAmbientDeferSessionDeactivation(active, options)) {
        return YES;
    }
    return %orig;
}
%end

%ctor { %init; }
