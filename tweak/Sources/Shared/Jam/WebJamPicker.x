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

// A button of ours over Spotify's, in the hosting view's superview: SwiftUI's gestures never see the touch,
// so its "Premium needed" error never comes. A tap starts the Web Jam and shows its code, a hold opens its
// settings. While the Web Jam runs the button is filled in the accent, flat, with a thin edge.
@interface SGWebJamOverlay : UIButton
@end

@implementation SGWebJamOverlay
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.accessibilityLabel = @"Web Jam";
        SGWebJamPressTarget *target = SGWebJamPressTarget.shared;
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        SGWebJamPress *press = [[SGWebJamPress alloc] initWithTarget:target action:@selector(pressed:)];
        press.minimumPressDuration = 0.45;
        press.target = CGRectInfinite;
        [self addGestureRecognizer:press];
    }
    return self;
}

- (void)tapped {
    openWebJam(@"tap");
    __weak UIView *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf.superview setNeedsLayout];
    });
}
@end

static char kOverlayKey;

static void markJam(UIView *host) {
    CGRect frame = jamFrame(host);
    // The element's frame runs above the drawn button (its label's line spacing); the button is the foot of it.
    if (!CGRectIsNull(frame) && frame.size.height > 62) frame = CGRectMake(frame.origin.x, CGRectGetMaxY(frame) - 58, frame.size.width, 56);
    SGWebJamOverlay *overlay = objc_getAssociatedObject(host, &kOverlayKey);
    UIView *holder = host.superview;
    if (CGRectIsNull(frame) || !holder) {
        overlay.hidden = YES;
        return;
    }
    if (!overlay) {
        overlay = [[SGWebJamOverlay alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &kOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"web jam: Start a Jam covered at %@", NSStringFromCGRect(frame));
    }
    if (overlay.superview != holder) [holder addSubview:overlay];
    else if (holder.subviews.lastObject != overlay) [holder bringSubviewToFront:overlay];
    CGRect inHolder = [holder convertRect:frame fromView:host];
    if (!CGRectEqualToRect(overlay.frame, inHolder)) overlay.frame = inHolder;
    overlay.hidden = NO;
    BOOL lit = SGWebJamRunning();
    UIColor *accent = (SGFusionAccent ? SGFusionAccent() : nil) ?: SGAccentMark();
    overlay.layer.cornerRadius = MIN(22, inHolder.size.height / 2);
    overlay.layer.cornerCurve = kCACornerCurveContinuous;
    overlay.backgroundColor = lit ? [accent colorWithAlphaComponent:0.3] : UIColor.clearColor;
    overlay.layer.borderWidth = lit ? 1 : 0;
    overlay.layer.borderColor = [accent colorWithAlphaComponent:0.7].CGColor;
    overlay.layer.shadowOpacity = 0;
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
