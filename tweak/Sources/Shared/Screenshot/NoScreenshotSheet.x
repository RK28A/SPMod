// Spotify opens its share sheet whenever a screenshot is taken. The notice it waits for is not passed on.
#import "Core/SGCore.h"

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    SGDebugOnce(@"hook Shared/Screenshot/NoScreenshotSheet.x: -[NSNotificationCenter postNotificationName:object:userInfo:] first call");
    if ([name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}

- (void)postNotification:(NSNotification *)notification {
    SGDebugOnce(@"hook Shared/Screenshot/NoScreenshotSheet.x: -[NSNotificationCenter postNotification:] first call");
    if ([notification.name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}
%end

%ctor {
    SGDebug(@"module Shared/Screenshot/NoScreenshotSheet.x on");
    %init;
}
