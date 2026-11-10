#import "Core/SGCore.h"
#import "Core/SGLog.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "App/About/About.h"
#import "Developer.h"

static UIWindow *frontWindow(void) {
    UIWindow *best = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha <= 0.01) continue;
            if (window.isKeyWindow) return window;
            if (!best || window.windowLevel >= best.windowLevel) best = window;
        }
    }
    return best;
}

static void dumpView(UIView *view, NSMutableString *out, int depth) {
    for (int i = 0; i < depth; i++) [out appendString:@"  "];
    [out appendFormat:@"%@ frame=%@", NSStringFromClass(view.class), NSStringFromCGRect(view.frame)];
    if (view.hidden) [out appendString:@" hidden"];
    if (view.alpha <= 0.01) [out appendString:@" alpha0"];
    if ([view isKindOfClass:UILabel.class]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length) [out appendFormat:@" text=\"%@\"", text];
    }
    if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [(UIButton *)view currentTitle];
        if (title.length) [out appendFormat:@" title=\"%@\"", title];
    }
    if (view.accessibilityIdentifier.length) [out appendFormat:@" id=%@", view.accessibilityIdentifier];
    if (view.accessibilityLabel.length) [out appendFormat:@" a11y=\"%@\"", view.accessibilityLabel];
    [out appendString:@"\n"];
    for (UIView *sub in view.subviews) dumpView(sub, out, depth + 1);
}

static NSString *treeOfFrontWindow(void) {
    UIWindow *window = frontWindow();
    if (!window) return @"No visible window found.";
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"// SPMod view tree — Spotify %@, iOS %@\n",
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
        UIDevice.currentDevice.systemVersion];
    UIViewController *root = window.rootViewController;
    if (root) [out appendFormat:@"// top controller: %@\n", NSStringFromClass(root.class)];
    dumpView(window, out, 0);
    return out;
}

static void confirm(NSString *message) {
    UIViewController *top = SGTopController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Developer" message:message
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void copyTreeNow(void) {
    UIPasteboard.generalPasteboard.string = treeOfFrontWindow();
    confirm(@"View tree copied to the clipboard.");
}

static void copyTreeDelayed(void) {
    UIViewController *top = SGTopController();
    [top dismissViewControllerAnimated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIPasteboard.generalPasteboard.string = treeOfFrontWindow();
            UINotificationFeedbackGenerator *haptic = [UINotificationFeedbackGenerator new];
            [haptic notificationOccurred:UINotificationFeedbackTypeSuccess];
        });
    }];
}

static void copyDiagnostics(void) {
    NSString *diagnostics = [NSString stringWithFormat:
        @"SPMod %s\nSpotify %@\niOS %@\nDevice %@",
        SG_VERSION,
        [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
        UIDevice.currentDevice.systemVersion,
        UIDevice.currentDevice.model];
    UIPasteboard.generalPasteboard.string = diagnostics;
    confirm(@"Diagnostics copied to the clipboard.");
}

UIViewController *SGDeveloperPage(void) {
    SGModSection *trees = SGNotedSection(@"View trees", @[
        SGWithSymbol(SGActionRow(@"Copy this screen's tree", @"Copies the current view hierarchy now", ^{ copyTreeNow(); }), @"doc.on.clipboard"),
        SGWithSymbol(SGActionRow(@"Copy a tree in 5 seconds", @"Closes settings; open the screen you want, it copies after 5s", ^{ copyTreeDelayed(); }), @"timer"),
    ], @"Paste the tree when reporting an issue so hooks can be matched to the real views.");

    SGModSection *logs = SGSection(@"Logs & diagnostics", @[
        SGWithSymbol(SGPageRow(@"Device logs", ^UIViewController *{ return SGDeviceLogsPage(); }), @"doc.text.magnifyingglass"),
        SGWithSymbol(SGActionRow(@"Copy diagnostics", @"App and device versions", ^{ copyDiagnostics(); }), @"info.circle"),
    ]);

    return [[SGModPage alloc] initWithTitle:@"Developer" intro:nil sections:@[trees, logs] footer:nil];
}
