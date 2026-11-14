#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fusion/Fusion.h"
#import "WebJam.h"

// The device picker's Start a Jam button (Connect_DevicePickerUIImpl.DevicePickerViewController, the recorded
// sheet) is SwiftUI's: no view to colour or to hold. It is found by its accessibility label in the hosting
// view's elements; with Web Jam running a ring in the accent is drawn over it, and a long press there opens
// the Web Jam sheet. The press is a recogniser on the hosting view that cancels nothing, so a tap still
// reaches Spotify's button.

static NSArray<NSString *> *kJamWords(void) {
    return @[@"lancer un jam", @"start a jam", @"jam starten", @"iniciar un jam", @"avvia una jam", @"jam"];
}

static void collect(id element, NSMutableArray *found, int depth) {
    if (depth > 6 || found.count > 300) return;
    NSArray *children = [element respondsToSelector:@selector(accessibilityElements)] ? [element accessibilityElements] : nil;
    if (!children.count && [element isKindOfClass:UIView.class]) children = ((UIView *)element).subviews;
    for (id child in children) {
        [found addObject:child];
        collect(child, found, depth + 1);
    }
}

// The Start a Jam element's frame in the hosting view, CGRectNull when it is not there.
static CGRect jamFrame(UIView *host) {
    static BOOL logged;
    NSMutableArray *elements = [NSMutableArray array];
    collect(host, elements, 0);
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (id element in elements) {
        NSString *label = [[element accessibilityLabel] lowercaseString];
        if (!label.length) continue;
        if (labels.count < 24) [labels addObject:label];
        for (NSString *word in kJamWords()) {
            if (![label hasPrefix:word]) continue;
            CGRect screen = [element accessibilityFrame];
            if (CGRectIsEmpty(screen)) continue;
            return [host convertRect:screen fromCoordinateSpace:host.window.screen.coordinateSpace];
        }
    }
    if (!logged) {
        logged = YES;
        SGLog(@"web jam: no Start a Jam button among the picker's %lu elements (%@), its place at the foot of the sheet is used", (unsigned long)elements.count,
              [labels componentsJoinedByString:@" | "]);
    }
    // The recorded sheet: Start a Jam is the left of the two buttons along its foot.
    CGSize size = host.bounds.size;
    if (size.height < 200) return CGRectNull;
    return CGRectMake(16, size.height - 118, size.width / 2 - 24, 70);
}

@interface SGWebJamPress : UILongPressGestureRecognizer
@property (nonatomic) CGRect target;
@end

@implementation SGWebJamPress
@end

static char kRingKey, kPressKey, kTapKey;

// Spotify's own Jam needs Premium on its server and only says an error came: the button starts the Web Jam
// instead and opens its sheet, a tap or a hold alike. Spotify never sees the touch.
static void openWebJam(NSString *how) {
    [[UIImpactFeedbackGenerator new] impactOccurred];
    BOOL was = SGWebJamRunning();
    if (!was) SGWebJamSetEnabled(YES);
    SGLog(@"web jam: %@ on Start a Jam, %@", how, was ? @"already running" : @"started");
    SGWebJamShowSheet();
}

@interface SGWebJamTap : UITapGestureRecognizer
@property (nonatomic) CGRect target;
@end

@implementation SGWebJamTap
@end

@interface SGWebJamPressTarget : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
@end

@implementation SGWebJamPressTarget
+ (instancetype)shared {
    static SGWebJamPressTarget *one;
    if (!one) one = [SGWebJamPressTarget new];
    return one;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    CGRect target = [gesture isKindOfClass:SGWebJamTap.class] ? ((SGWebJamTap *)gesture).target : ((SGWebJamPress *)gesture).target;
    return !CGRectIsNull(target) && CGRectContainsPoint(CGRectInset(target, -6, -6), [gesture locationInView:gesture.view]);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return NO;
}

- (void)tapped:(SGWebJamTap *)tap {
    if (tap.state == UIGestureRecognizerStateEnded) openWebJam(@"tap");
}

// A hold opens the Web Jam's settings page over the picker, in a navigation of its own.
- (void)pressed:(SGWebJamPress *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    UIViewController *top = SGTopController();
    UIViewController *page = SGWebJamPage();
    if (!top || !page) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:page];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    page.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose primaryAction:
        [UIAction actionWithHandler:^(UIAction *action) { [navigation dismissViewControllerAnimated:YES completion:nil]; }] menu:nil];
    SGLog(@"web jam: long press on Start a Jam, its settings opened");
    [top presentViewController:navigation animated:YES completion:nil];
}
@end

static void markJam(UIView *host) {
    CGRect frame = jamFrame(host);
    CAShapeLayer *ring = objc_getAssociatedObject(host, &kRingKey);
    SGWebJamPress *press = objc_getAssociatedObject(host, &kPressKey);
    SGWebJamTap *tap = objc_getAssociatedObject(host, &kTapKey);
    if (!press) {
        SGWebJamPressTarget *target = SGWebJamPressTarget.shared;
        press = [[SGWebJamPress alloc] initWithTarget:target action:@selector(pressed:)];
        press.delegate = target;
        press.minimumPressDuration = 0.45;
        [host addGestureRecognizer:press];
        objc_setAssociatedObject(host, &kPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        tap = [[SGWebJamTap alloc] initWithTarget:target action:@selector(tapped:)];
        tap.delegate = target;
        [tap requireGestureRecognizerToFail:press];
        [host addGestureRecognizer:tap];
        objc_setAssociatedObject(host, &kTapKey, tap, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGDebug(@"web jam: Start a Jam taken over at %@", NSStringFromCGRect(frame));
    }
    press.target = frame;
    tap.target = frame;
    BOOL lit = SGWebJamRunning() && !CGRectIsNull(frame);
    if (!lit) {
        ring.hidden = YES;
        return;
    }
    if (!ring) {
        ring = [CAShapeLayer layer];
        ring.fillColor = nil;
        ring.lineWidth = 2;
        objc_setAssociatedObject(host, &kRingKey, ring, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (ring.superlayer != host.superview.layer) [host.superview.layer addSublayer:ring];
    UIColor *accent = (SGFusionAccent ? SGFusionAccent() : nil) ?: SGAccentMark();
    CGRect inHost = [host.superview convertRect:frame fromView:host];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.hidden = NO;
    ring.zPosition = 10;
    ring.strokeColor = accent.CGColor;
    ring.fillColor = [accent colorWithAlphaComponent:0.32].CGColor;
    ring.shadowColor = accent.CGColor;
    ring.shadowOpacity = 0.7;
    ring.shadowRadius = 8;
    ring.shadowOffset = CGSizeZero;
    ring.path = [UIBezierPath bezierPathWithRoundedRect:inHost cornerRadius:MIN(22, inHost.size.height / 2)].CGPath;
    [CATransaction commit];
}

%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
- (void)viewDidLayoutSubviews {
    SGDebugOnce(@"hook Shared/Jam/WebJamPicker.x: -[DevicePickerViewController viewDidLayoutSubviews] first call");
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    for (UIView *sub in page.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"UIHostingView"]) markJam(sub);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    SGDebugOnce(@"hook Shared/Jam/WebJamPicker.x: -[DevicePickerViewController viewDidAppear:] first call");
    %orig;
    // SwiftUI lays out the buttons after the first pass: once more when they are there.
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for (UIView *sub in page.subviews) {
            if ([NSStringFromClass(sub.class) containsString:@"UIHostingView"]) markJam(sub);
        }
    });
}
%end

%ctor {
    SGDebug(@"module Shared/Jam/WebJamPicker.x on");
    %init;
}
