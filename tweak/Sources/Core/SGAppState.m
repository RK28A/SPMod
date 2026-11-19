#import <UIKit/UIKit.h>
#import <stdatomic.h>
#import "SGAppState.h"
#import "SGLog.h"

static atomic_bool sg_back;

BOOL SGAppInBackground(void) {
    return atomic_load(&sg_back);
}

__attribute__((constructor)) static void watchAppState(void) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        atomic_store(&sg_back, true);
        SGDebug(@"app: in the background, idle work rests");
    }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        atomic_store(&sg_back, false);
        SGDebug(@"app: in front again");
    }];
}
