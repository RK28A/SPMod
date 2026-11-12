// Spotify opens its share sheet whenever a screenshot is taken. The notice it waits for is not passed on.
#import "Core/SGCore.h"

%hook NSNotificationCenter
- (void)postNotificationName:(NSNotificationName)name object:(id)object userInfo:(NSDictionary *)userInfo {
    if ([name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}

- (void)postNotification:(NSNotification *)notification {
    if ([notification.name isEqualToString:UIApplicationUserDidTakeScreenshotNotification]) return;
    %orig;
}
%end

%ctor {
    %init;
}
