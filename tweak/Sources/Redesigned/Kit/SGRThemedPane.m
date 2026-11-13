#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "SGRAccentWash.h"
#import "SGRThemedPane.h"
#import "SGRGlassSettings.h"

static char kStyleKey;

// Style 3 (Outline) is no glass at all: a bright rim on a breath of white, the lightest to draw.
static UIView *newCard(void) {
    UIView *card = nil;
    if (SGRGlassStyleNow() == 3) {
        card = [UIView new];
        card.backgroundColor = [UIColor colorWithWhite:1 alpha:0.05];
        card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.2].CGColor;
        card.layer.borderWidth = 0.75;
        card.layer.cornerCurve = kCACornerCurveContinuous;
    } else {
        card = [[UIVisualEffectView alloc] initWithEffect:SGRGlassEffectNow()];
        card.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        // Clear: the system's clear glass still greys what is behind it. The fill sets how much of it shows,
        // a third at 0% (the bend of the light and a rim, the background seen as it is), all of it at 100%.
        if (SGRGlassStyleNow() == 1) {
            double fill = SGRGlassClearFill();
            card.alpha = 0.32 + 0.68 * fill;
            card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35 - 0.2 * fill].CGColor;
            card.layer.borderWidth = 1;
        }
    }
    objc_setAssociatedObject(card, &kStyleKey, @(SGRGlassLookNow()), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    card.userInteractionEnabled = NO;
    card.accessibilityElementsHidden = YES;
    return card;
}

void SGRGlassCard(UIView *row, const void *key, CGRect frame, CGFloat radius, BOOL wanted) {
    UIView *card = objc_getAssociatedObject(row, key);
    if (!wanted || frame.size.width < 1 || frame.size.height < 1) {
        if (card.superview) [card removeFromSuperview];
        return;
    }
    // A style chosen in Liquid Glass reaches the cards on screen at their next pass, each as a new card: an
    // effect view keeps the look of the glass it was made with when it is only handed another.
    if (card && [objc_getAssociatedObject(card, &kStyleKey) integerValue] != SGRGlassLookNow()) {
        [card removeFromSuperview];
        card = nil;
    }
    if (!card) {
        card = newCard();
        objc_setAssociatedObject(row, key, card, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Kept behind by its layer's depth, never by moving it among the row's views: a view moved during a
    // layout pass lays its parent out again, and a list that puts its own views back in its order on every
    // pass then never finishes laying out (the playlist frozen black behind its curtain).
    if (card.superview != row) {
        SGLoopNote("glass card inserted");
        [row insertSubview:card atIndex:0];
    }
    if (card.layer.zPosition != -50) card.layer.zPosition = -50;
    if (CGRectEqualToRect(card.frame, frame)) return;
    SGLoopNote("glass card frame");
    card.frame = frame;
    if ([card isKindOfClass:UIVisualEffectView.class]) SGShapeGlass(card, radius, NO);
    else card.layer.cornerRadius = radius;
}

// The pane starts this far above the first track and comes in over that distance, so the theme rises out of
// the cover's field with no edge where one stops and the other starts. Once the list has scrolled the pane
// to the top of the screen there is nothing left to come in over, and the mask is taken off.
static const CGFloat kLead = 170;

@interface SGRThemedPaneView : UIView
@property (nonatomic) CGFloat top;
@property (nonatomic) CGFloat lead;   // how much of the top is fading in now, -1 before the first pass
@property (nonatomic, strong) CAGradientLayer *veil;
@end

@implementation SGRThemedPaneView
@end

static char kPaneKey;

static void fadeIn(SGRThemedPaneView *pane, CGFloat lead) {
    CGFloat height = pane.bounds.size.height;
    if (height < 1) return;
    // The mask stays once given; with nothing coming in its gradient starts fully drawn.
    lead = MAX(0, lead);
    if (!pane.veil) {
        pane.veil = [CAGradientLayer layer];
        pane.veil.colors = @[(id)UIColor.clearColor.CGColor, (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor, (id)UIColor.blackColor.CGColor];
    }
    if (pane.layer.mask != pane.veil) {
        SGLoopNote("pane mask");
        pane.layer.mask = pane.veil;
    }
    if (!CGRectEqualToRect(pane.veil.frame, pane.bounds)) pane.veil.frame = pane.bounds;
    if (fabs(pane.lead - lead) < 0.5) return;
    pane.lead = lead;
    pane.veil.locations = @[@0, @(lead * 0.6 / height), @(lead / height)];
}

void SGRThemedPaneFollow(UIScrollView *list) {
    SGRThemedPaneView *pane = objc_getAssociatedObject(list, &kPaneKey);
    if (!pane.superview) return;
    CGSize size = list.bounds.size;
    CGFloat y = MAX(pane.top - kLead, list.contentOffset.y);
    CGRect frame = CGRectMake(0, y, size.width, size.height);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (!CGRectEqualToRect(pane.frame, frame)) {
        SGLoopNote("pane frame");
        pane.frame = frame;
    }
    fadeIn(pane, MIN(kLead, MAX(0, pane.top - y)));
    [CATransaction commit];
    if (pane.layer.zPosition != -100) pane.layer.zPosition = -100;
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
        pane.lead = -1;
        objc_setAssociatedObject(list, &kPaneKey, pane, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (pane.superview != list) {
        SGLoopNote("pane inserted");
        [list insertSubview:pane atIndex:0];
    }
    pane.top = top;
    SGRThemedPaneFollow(list);
    SGRAccentWashPlace(pane);
}
