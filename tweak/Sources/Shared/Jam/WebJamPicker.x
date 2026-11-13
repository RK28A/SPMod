#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
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
        SGLog(@"web jam: no Start a Jam button among the picker's %lu elements (%@)", (unsigned long)elements.count,
              [labels componentsJoinedByString:@" | "]);
    }
    return CGRectNull;
}

@interface SGWebJamPress : UILongPressGestureRecognizer
@property (nonatomic) CGRect target;
@end

@implementation SGWebJamPress
@end

static char kRingKey, kPressKey;

@interface SGWebJamPressTarget : NSObject
+ (void)pressed:(SGWebJamPress *)press;
@end

@implementation SGWebJamPressTarget
+ (void)pressed:(SGWebJamPress *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    CGPoint at = [press locationInView:press.view];
    if (!CGRectContainsPoint(CGRectInset(press.target, -8, -8), at)) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    SGLog(@"web jam: long press on Start a Jam");
    SGWebJamShowSheet();
}
@end

static void markJam(UIView *host) {
    CGRect frame = jamFrame(host);
    CAShapeLayer *ring = objc_getAssociatedObject(host, &kRingKey);
    SGWebJamPress *press = objc_getAssociatedObject(host, &kPressKey);
    if (!press) {
        press = [[SGWebJamPress alloc] initWithTarget:SGWebJamPressTarget.class action:@selector(pressed:)];
        press.cancelsTouchesInView = NO;
        press.delaysTouchesBegan = NO;
        press.minimumPressDuration = 0.45;
        [host addGestureRecognizer:press];
        objc_setAssociatedObject(host, &kPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    press.target = frame;
    press.enabled = !CGRectIsNull(frame);
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
    UIColor *accent = host.tintColor ?: UIColor.systemGreenColor;
    CGRect inHost = [host.superview convertRect:frame fromView:host];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    ring.hidden = NO;
    ring.zPosition = 10;
    ring.strokeColor = accent.CGColor;
    ring.fillColor = [accent colorWithAlphaComponent:0.18].CGColor;
    ring.shadowColor = accent.CGColor;
    ring.shadowOpacity = 0.7;
    ring.shadowRadius = 8;
    ring.shadowOffset = CGSizeZero;
    ring.path = [UIBezierPath bezierPathWithRoundedRect:inHost cornerRadius:MIN(22, inHost.size.height / 2)].CGPath;
    [CATransaction commit];
}

%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    for (UIView *sub in page.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"UIHostingView"]) markJam(sub);
    }
}

- (void)viewDidAppear:(BOOL)animated {
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
    %init;
}
