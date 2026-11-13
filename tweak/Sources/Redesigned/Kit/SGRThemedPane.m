#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "SGRAccentWash.h"
#import "SGRThemedPane.h"
#import "SGRGlassSettings.h"

static char kStyleKey;

void SGRGlassCard(UIView *row, const void *key, CGRect frame, CGFloat radius, BOOL wanted) {
    UIVisualEffectView *card = objc_getAssociatedObject(row, key);
    if (!wanted || frame.size.width < 1 || frame.size.height < 1) {
        if (card.superview) [card removeFromSuperview];
        return;
    }
    if (!card) {
        card = [[UIVisualEffectView alloc] initWithEffect:SGRGlassEffectNow()];
        objc_setAssociatedObject(card, &kStyleKey, @(SGRGlassStyleNow()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        card.userInteractionEnabled = NO;
        card.accessibilityElementsHidden = YES;
        card.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        objc_setAssociatedObject(row, key, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // The style chosen in Liquid Glass reaches the cards on screen at their next pass.
    if ([objc_getAssociatedObject(card, &kStyleKey) integerValue] != SGRGlassStyleNow()) {
        card.effect = SGRGlassEffectNow();
        objc_setAssociatedObject(card, &kStyleKey, @(SGRGlassStyleNow()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (card.superview != row) [row insertSubview:card atIndex:0];
    else if (row.subviews.firstObject != card) [row sendSubviewToBack:card];
    if (CGRectEqualToRect(card.frame, frame)) return;
    card.frame = frame;
    SGShapeGlass(card, radius, NO);
}

@interface SGRThemedPaneView : UIView
@property (nonatomic) CGFloat top;
@property (nonatomic, strong) UIVisualEffectView *sheet;
@end

@implementation SGRThemedPaneView
@end

static char kPaneKey;

void SGRThemedPaneFollow(UIScrollView *list) {
    SGRThemedPaneView *pane = objc_getAssociatedObject(list, &kPaneKey);
    if (!pane.superview) return;
    CGSize size = list.bounds.size;
    CGRect frame = CGRectMake(0, MAX(pane.top, list.contentOffset.y), size.width, size.height);
    if (!CGRectEqualToRect(pane.frame, frame)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        pane.frame = frame;
        pane.sheet.frame = pane.bounds;
        [CATransaction commit];
    }
    if (list.subviews.firstObject != pane) [list sendSubviewToBack:pane];
}

void SGRThemedPane(UIScrollView *list, CGFloat top) {
    SGRThemedPaneView *pane = objc_getAssociatedObject(list, &kPaneKey);
    if (top < 0) {
        [pane removeFromSuperview];
        return;
    }
    if (!pane) {
        pane = [SGRThemedPaneView new];
        pane.userInteractionEnabled = NO;
        pane.clipsToBounds = YES;
        objc_setAssociatedObject(list, &kPaneKey, pane, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (pane.superview != list) [list insertSubview:pane atIndex:0];
    pane.top = top;
    SGRThemedPaneFollow(list);
    // The theme under the sheet, at the back of the pane; the sheet over it.
    SGRAccentWashPlace(pane);
}
