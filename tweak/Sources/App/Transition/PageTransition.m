#import "Core/SGCore.h"
#import "Settings/SGBackdrop.h"
#import "Settings/SGPageStyle.h"
#import "PageTransition.h"

static const NSTimeInterval kIn = 0.1, kOut = 0.42, kPush = 0.4, kLongest = 1.6;

NSArray<NSString *> *SGPageTransitionNames(void) {
    return @[@"Off", @"Fade", @"Zoom", @"Rise", @"Blur", @"Circle", @"Curtain", @"Glass"];
}

NSArray<NSString *> *SGPageTransitionNotes(void) {
    return @[@"Spotify's own: the menu closes onto Home, then the page comes.",
             @"The page fades in straight from the menu.",
             @"The page comes forward out of the background.",
             @"The background lifts away upward, the page under it.",
             @"The background melts into a blur that clears onto the page.",
             @"The page opens in a circle from where you tapped.",
             @"The background parts in two from the middle.",
             @"A pane of glass clears off the page."];
}

static UIView *sg_veil;
static CGPoint sg_from;

static UIWindow *mainWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if ([window.accessibilityIdentifier isEqualToString:@"spotify-main-window"]) return window;
        }
    }
    return SGTopController().view.window;
}

static void finish(UIView *veil) {
    [veil removeFromSuperview];
    if (sg_veil == veil) sg_veil = nil;
}

static void away(UIView *veil) {
    NSInteger style = SGInt(SGKeyPageTransition, SGPageTransitionZoom);
    CGRect bounds = veil.bounds;
    SGDebug(@"page transition: away in style %@", SGPageTransitionNames()[MIN(MAX(style, 0), 7)]);
    void (^done)(BOOL) = ^(BOOL ended) { finish(veil); };
    UIViewAnimationOptions ease = UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionAllowUserInteraction;
    switch (style) {
        case SGPageTransitionZoom:
            [UIView animateWithDuration:kOut delay:0 options:ease animations:^{
                veil.transform = CGAffineTransformMakeScale(1.18, 1.18);
                veil.alpha = 0;
            } completion:done];
            break;
        case SGPageTransitionRise:
            [UIView animateWithDuration:kOut delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0 options:ease animations:^{
                veil.transform = CGAffineTransformMakeTranslation(0, -bounds.size.height);
            } completion:done];
            break;
        case SGPageTransitionBlur: {
            UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:nil];
            blur.frame = bounds;
            [veil addSubview:blur];
            [UIView animateWithDuration:kOut * 0.45 animations:^{
                blur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark];
            } completion:^(BOOL ended) {
                for (UIView *sub in veil.subviews) if (sub != blur) sub.alpha = 0;
                veil.backgroundColor = UIColor.clearColor;
                [UIView animateWithDuration:kOut * 0.7 animations:^{ blur.effect = nil; } completion:done];
            }];
            break;
        }
        case SGPageTransitionCircle: {
            CGFloat reach = hypot(MAX(sg_from.x, bounds.size.width - sg_from.x), MAX(sg_from.y, bounds.size.height - sg_from.y));
            CAShapeLayer *mask = [CAShapeLayer layer];
            mask.fillRule = kCAFillRuleEvenOdd;
            mask.frame = bounds;
            UIBezierPath *start = [UIBezierPath bezierPathWithRect:bounds], *end = [UIBezierPath bezierPathWithRect:bounds];
            [start appendPath:[UIBezierPath bezierPathWithArcCenter:sg_from radius:1 startAngle:0 endAngle:2 * M_PI clockwise:YES]];
            [end appendPath:[UIBezierPath bezierPathWithArcCenter:sg_from radius:reach startAngle:0 endAngle:2 * M_PI clockwise:YES]];
            mask.path = end.CGPath;
            veil.layer.mask = mask;
            [CATransaction begin];
            [CATransaction setCompletionBlock:^{ finish(veil); }];
            CABasicAnimation *open = [CABasicAnimation animationWithKeyPath:@"path"];
            open.fromValue = (__bridge id)start.CGPath;
            open.toValue = (__bridge id)end.CGPath;
            open.duration = kOut * 1.1;
            open.timingFunction = [CAMediaTimingFunction functionWithControlPoints:0.3 :0 :0.2 :1];
            [mask addAnimation:open forKey:@"open"];
            [CATransaction commit];
            break;
        }
        case SGPageTransitionCurtain: {
            UIView *left = [veil resizableSnapshotViewFromRect:CGRectMake(0, 0, bounds.size.width / 2, bounds.size.height) afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
            UIView *right = [veil resizableSnapshotViewFromRect:CGRectMake(bounds.size.width / 2, 0, bounds.size.width / 2, bounds.size.height) afterScreenUpdates:NO withCapInsets:UIEdgeInsetsZero];
            if (!left || !right) {
                [UIView animateWithDuration:kOut animations:^{ veil.alpha = 0; } completion:done];
                break;
            }
            right.frame = CGRectOffset(right.bounds, bounds.size.width / 2, 0);
            for (UIView *sub in veil.subviews) [sub removeFromSuperview];
            veil.backgroundColor = UIColor.clearColor;
            [veil addSubview:left];
            [veil addSubview:right];
            [UIView animateWithDuration:kOut delay:0 options:ease animations:^{
                left.transform = CGAffineTransformMakeTranslation(-bounds.size.width / 2, 0);
                right.transform = CGAffineTransformMakeTranslation(bounds.size.width / 2, 0);
            } completion:done];
            break;
        }
        case SGPageTransitionGlass: {
            UIVisualEffectView *pane = nil;
            if (@available(iOS 26.0, *)) pane = [[UIVisualEffectView alloc] initWithEffect:[UIGlassEffect effectWithStyle:UIGlassEffectStyleClear]];
            else pane = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
            pane.frame = bounds;
            pane.layer.cornerRadius = 44;
            pane.layer.cornerCurve = kCACornerCurveContinuous;
            pane.clipsToBounds = YES;
            pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
            for (UIView *sub in veil.subviews) [sub removeFromSuperview];
            veil.backgroundColor = UIColor.clearColor;
            [veil addSubview:pane];
            [UIView animateWithDuration:kOut * 1.2 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:ease animations:^{
                pane.transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0, bounds.size.height * 0.6), 0.86, 0.86);
                pane.alpha = 0;
            } completion:done];
            break;
        }
        default:
            [UIView animateWithDuration:kOut delay:0 options:ease animations:^{ veil.alpha = 0; } completion:done];
    }
}

// The menu closes first (the top becomes Home), then the page is pushed (the top becomes the page): the veil
// waits for a second change, or for a first one that stays half a second, or for kLongest.
static void waitForPage(UIView *veil, UIViewController *was, UIViewController *first, CFTimeInterval since, CFTimeInterval firstAt) {
    if (sg_veil != veil) return;
    UIViewController *now = SGTopController();
    CFTimeInterval clock = CACurrentMediaTime();
    BOOL settled = NO;
    if (now && now != was) {
        if (!first) {
            first = now;
            firstAt = clock;
        } else if (now != first) {
            settled = YES;
        } else if (clock - firstAt > 0.5) {
            settled = YES;
        }
    }
    if (!settled && clock - since < kLongest) {
        __weak UIViewController *weakFirst = first;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            waitForPage(veil, was, weakFirst, since, firstAt);
        });
        return;
    }
    if (!settled) SGLog(@"page transition: no new page within %.1f s, the veil goes anyway", kLongest);
    else SGDebug(@"page transition: %@ is on top", NSStringFromClass(now.class));
    // The page is pushed under the veil: it goes once the push has settled.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((settled ? kPush : 0) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_veil == veil) away(veil);
    });
}

void SGPageVeilUp(CGPoint point) {
    NSInteger style = SGInt(SGKeyPageTransition, SGPageTransitionZoom);
    if (style == SGPageTransitionOff || UIAccessibilityIsReduceMotionEnabled() || sg_veil) return;
    UIWindow *window = mainWindow();
    if (!window) return;
    sg_from = point;
    UIView *veil = [[UIView alloc] initWithFrame:window.bounds];
    veil.backgroundColor = UIColor.blackColor;
    veil.userInteractionEnabled = YES;
    veil.alpha = 0;
    [window addSubview:veil];
    // The page's own background, so the veil is the page before the page is there.
    SGBackdropPlace(veil);
    sg_veil = veil;
    SGDebug(@"page transition: veil up from %@", NSStringFromCGPoint(point));
    UIViewController *was = SGTopController();
    [UIView animateWithDuration:kIn animations:^{ veil.alpha = 1; } completion:^(BOOL ended) {
        waitForPage(veil, was, nil, CACurrentMediaTime(), 0);
    }];
}
