#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGREntrance.h"

static NSString *const kEnter = @"sgr.enter";

void SGREntrance(UIView *row, UIScrollView *list) {
    static char kPlaceKey;
    if (!row.window || !list) return;
    CGFloat top = CGRectGetMinY(row.frame);
    NSNumber *was = objc_getAssociatedObject(row, &kPlaceKey);
    if (was && fabs(was.doubleValue - top) < 1) return;
    objc_setAssociatedObject(row, &kPlaceKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSInteger level = SGInt(SGRKeyEntrance, 1);
    if (level <= 0 || UIAccessibilityIsReduceMotionEnabled() || [row.layer animationForKey:kEnter]) return;
    CGFloat height = MAX(1, list.bounds.size.height), place = (top - list.contentOffset.y) / height;
    if (place < -0.2 || place > 1.2) return;
    BOOL lively = level >= 2;
    // A list at rest is a page opening: its rows follow each other down. One being scrolled brings them in at once.
    CFTimeInterval wait = list.isDragging || list.isDecelerating ? 0 : MIN(0.4, MAX(0, place) * (lively ? 0.5 : 0.3));
    CALayer *layer = row.layer;

    CASpringAnimation *settle = [CASpringAnimation animationWithKeyPath:@"transform"];
    CGFloat from = lively ? 0.9 : 0.965;
    settle.fromValue = [NSValue valueWithCATransform3D:CATransform3DTranslate(CATransform3DMakeScale(from, from, 1), 0, lively ? 26 : 12, 0)];
    settle.mass = 1;
    settle.stiffness = lively ? 190 : 260;
    settle.damping = lively ? 17 : 28;
    settle.duration = settle.settlingDuration;

    CABasicAnimation *appear = [CABasicAnimation animationWithKeyPath:@"opacity"];
    appear.fromValue = @0;
    appear.duration = lively ? 0.32 : 0.22;

    CAAnimationGroup *enter = [CAAnimationGroup animation];
    enter.animations = @[settle, appear];
    enter.duration = MAX(settle.duration, appear.duration);
    enter.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] + wait;
    enter.fillMode = kCAFillModeBackwards;
    enter.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    SGLoopNote("row entrance");
    [layer addAnimation:enter forKey:kEnter];
}
