#import "Core/SGCore.h"
#import "Core/SGLog.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "App/About/About.h"
#import "Developer.h"

@interface SGTreeWindow : UIWindow
@end

@implementation SGTreeWindow

// Only the button takes touches: the rest of the window lets them through to the app under it.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self || hit == self.rootViewController.view ? nil : hit;
}

@end

static UIWindow *frontWindow(void) {
    UIWindow *best = nil;
    // Spotify's own window first: the keyboard's and the text effects' windows are often key and hold nothing.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && [window.accessibilityIdentifier isEqualToString:@"spotify-main-window"] && !SGTopController().presentedViewController) return window;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha <= 0.01 || [window isKindOfClass:SGTreeWindow.class]) continue;
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

// The tree button: a small round button that stays over the app, above every screen, until it is held. A tap
// takes the tree of the screen under it: copied to the clipboard and kept as a file (Documents/SPMod
// trees/), with a word saying so. It can be dragged anywhere.
static SGTreeWindow *sg_treeWindow;

static NSURL *saveTree(NSString *tree) {
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [documents URLByAppendingPathComponent:@"SPMod trees" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSDateFormatter *format = [NSDateFormatter new];
    format.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    NSURL *file = [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"tree %@.txt", [format stringFromDate:NSDate.date]]];
    return [tree writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:nil] ? file : nil;
}

@interface SGTreeButton : UIButton
@end

@implementation SGTreeButton {
    UILabel *_word;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
    [self setImage:[UIImage systemImageNamed:@"tree.fill" withConfiguration:config] forState:UIControlStateNormal];
    self.tintColor = UIColor.whiteColor;
    self.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:0.25 alpha:0.92];
    self.layer.cornerRadius = frame.size.width / 2;
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    self.layer.shadowOpacity = 0.4;
    self.layer.shadowRadius = 6;
    self.layer.shadowOffset = CGSizeMake(0, 2);
    self.accessibilityLabel = @"Take this screen's view tree";
    [self addTarget:self action:@selector(take) forControlEvents:UIControlEventTouchUpInside];
    [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)];
    hold.minimumPressDuration = 0.8;
    [self addGestureRecognizer:hold];
    return self;
}

- (void)say:(NSString *)text {
    UIView *host = self.superview;
    if (!host) return;
    [_word removeFromSuperview];
    _word = [UILabel new];
    _word.text = [NSString stringWithFormat:@"  %@  ", text];
    _word.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _word.textColor = UIColor.whiteColor;
    _word.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.94];
    _word.layer.cornerRadius = 12;
    _word.clipsToBounds = YES;
    _word.numberOfLines = 2;
    CGSize fit = [_word sizeThatFits:CGSizeMake(host.bounds.size.width - 40, 60)];
    CGFloat x = MIN(MAX(12, self.center.x - fit.width / 2), host.bounds.size.width - fit.width - 12);
    CGFloat y = self.frame.origin.y > 120 ? self.frame.origin.y - fit.height - 18 : CGRectGetMaxY(self.frame) + 8;
    _word.frame = CGRectMake(x, y, fit.width, fit.height + 10);
    [host addSubview:_word];
    UILabel *word = _word;
    [UIView animateWithDuration:0.3 delay:2.2 options:0 animations:^{ word.alpha = 0; } completion:^(BOOL done) { [word removeFromSuperview]; }];
}

- (void)take {
    NSString *tree = treeOfFrontWindow();
    UIPasteboard.generalPasteboard.string = tree;
    NSURL *file = saveTree(tree);
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    [self say:file ? @"Tree copied to the clipboard (a copy is kept in SPMod trees)" : @"Tree copied to the clipboard"];
    SGLog(@"developer: tree taken (%lu lines)%@", (unsigned long)[tree componentsSeparatedByString:@"\n"].count, file ? @", saved" : @"");
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    UIView *host = self.superview;
    CGPoint moved = [pan translationInView:host];
    [pan setTranslation:CGPointZero inView:host];
    CGRect area = UIEdgeInsetsInsetRect(host.bounds, host.safeAreaInsets);
    CGFloat half = self.bounds.size.width / 2;
    self.center = CGPointMake(MIN(MAX(self.center.x + moved.x, CGRectGetMinX(area) + half), CGRectGetMaxX(area) - half),
                              MIN(MAX(self.center.y + moved.y, CGRectGetMinY(area) + half), CGRectGetMaxY(area) - half));
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    sg_treeWindow.hidden = YES;
    sg_treeWindow = nil;
}

@end

static void showTreeButton(void) {
    if (sg_treeWindow) return;
    UIWindowScene *scene = SGTopController().view.window.windowScene;
    if (!scene) return;
    SGTreeWindow *window = [[SGTreeWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert + 10;
    window.backgroundColor = UIColor.clearColor;
    UIViewController *root = [UIViewController new];
    root.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = root;
    CGRect bounds = window.bounds;
    SGTreeButton *button = [[SGTreeButton alloc] initWithFrame:CGRectMake(bounds.size.width - 72, bounds.size.height * 0.42, 52, 52)];
    [root.view addSubview:button];
    window.hidden = NO;
    sg_treeWindow = window;
}

static void startTreeButton(void) {
    UIViewController *top = SGTopController();
    showTreeButton();
    // Out of the settings, so the screen to take is the one under them.
    if (top.presentingViewController) [top.presentingViewController dismissViewControllerAnimated:YES completion:nil];
    else [top.navigationController popToRootViewControllerAnimated:YES];
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
        SGWithSymbol(SGActionRow(@"Click on icon for tree", @"Puts a tree button over the app: open any screen and tap it", ^{ startTreeButton(); }), @"tree"),
    ], @"Tap the tree button on the screen you want: its tree is copied to the clipboard. Drag it out of the way; hold it to put it away.");

    SGModSection *logs = SGSection(@"Logs & diagnostics", @[
        SGWithSymbol(SGPageRow(@"Device logs", ^UIViewController *{ return SGDeviceLogsPage(); }), @"doc.text.magnifyingglass"),
        SGWithSymbol(SGActionRow(@"Copy diagnostics", @"App and device versions", ^{ copyDiagnostics(); }), @"info.circle"),
    ]);

    return [[SGModPage alloc] initWithTitle:@"Developer" intro:nil sections:@[trees, logs] footer:nil];
}
