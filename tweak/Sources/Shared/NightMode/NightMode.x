#import "Core/SGCore.h"
#import "Core/SGPrefs.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "NightMode.h"

static NSString *const kEnabled = @"spotifyglass.nightmode.enabled";
static NSString *const kStart = @"spotifyglass.nightmode.start";
static NSString *const kEnd = @"spotifyglass.nightmode.end";
static NSString *const kDim = @"spotifyglass.nightmode.dim";

static UIWindow *gOverlay;
static NSTimer *gTimer;

static BOOL nightActive(void) {
    if (!SGHidden(kEnabled)) return NO;
    NSDateComponents *now = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:NSDate.date];
    NSInteger minutes = now.hour * 60 + now.minute;
    NSInteger start = SGInt(kStart, 22 * 60);
    NSInteger end = SGInt(kEnd, 7 * 60);
    if (start == end) return YES;
    return start < end ? (minutes >= start && minutes < end) : (minutes >= start || minutes < end);
}

static UIWindowScene *activeScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive)
            return (UIWindowScene *)scene;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) return (UIWindowScene *)scene;
    return nil;
}

static void refreshNightMode(void) {
    if (!nightActive()) {
        gOverlay.hidden = YES;
        return;
    }

    if (!gOverlay) {
        UIWindowScene *scene = activeScene();
        if (!scene) return;
        gOverlay = [[UIWindow alloc] initWithWindowScene:scene];
        gOverlay.windowLevel = UIWindowLevelAlert + 2;
        gOverlay.userInteractionEnabled = NO;
        gOverlay.backgroundColor = UIColor.blackColor;
    }

    CGFloat dim = MIN(MAX(SGInt(kDim, 25), 0), 70) / 100.0;
    gOverlay.alpha = dim;
    gOverlay.hidden = NO;
}

static NSString *formatTime(double value) {
    NSInteger total = (NSInteger)value;
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(total / 60), (long)(total % 60)];
}

UIViewController *SGNightModeSettingsPage(void) {
    SGModRow *enabled = SGHideRow(@"Enable night mode", @"Dims the whole app during the chosen hours", kEnabled);

    SGModRow *start = SGSliderRow(@"Start", nil, 0, 1439, 15,
        ^double{ return SGInt(kStart, 22 * 60); },
        ^(double value) { SGSetInt(kStart, (NSInteger)value); refreshNightMode(); },
        ^NSString *(double value) { return formatTime(value); });

    SGModRow *end = SGSliderRow(@"End", nil, 0, 1439, 15,
        ^double{ return SGInt(kEnd, 7 * 60); },
        ^(double value) { SGSetInt(kEnd, (NSInteger)value); refreshNightMode(); },
        ^NSString *(double value) { return formatTime(value); });

    SGModRow *dim = SGSliderRow(@"Dim level", nil, 0, 70, 5,
        ^double{ return SGInt(kDim, 25); },
        ^(double value) { SGSetInt(kDim, (NSInteger)value); refreshNightMode(); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d%%", (int)value]; });

    SGModSection *section = SGSection(nil, @[
        SGWithSymbol(enabled, @"moon.stars"),
        start, end, dim,
    ]);
    return [[SGModPage alloc] initWithTitle:@"Night mode" intro:nil sections:@[section] footer:nil];
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        gTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
            refreshNightMode();
        }];
        refreshNightMode();
    });
}
