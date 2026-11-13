#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRAccent.h"
#import "SGRTokens.h"
#import "SGRAccentWash.h"
#import "Settings/SGBackdrop.h"

static const CGFloat kReach = 0.55, kStrength = 0.30;
static const CFTimeInterval kFade = 0.7;
static char kWashKey;

@interface SGRAccentWashView : UIView
@end

@implementation SGRAccentWashView

+ (Class)layerClass {
    return CAGradientLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.isAccessibilityElement = NO;
        // The whole page's ground: Spotify's own fills above it are cleared, so the black is this view's.
        self.backgroundColor = UIColor.blackColor;
        CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
        gradient.startPoint = CGPointMake(0.5, 0);
        gradient.endPoint = CGPointMake(0.5, kReach);
        [self paint:NO];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accentChanged) name:SGRAccentDidChangeNotification object:nil];
    }
    return self;
}

- (void)accentChanged {
    [self paint:self.window != nil];
}

- (void)paint:(BOOL)animated {
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    UIColor *accent = SGRAccent();
    NSArray *colors = @[(id)[accent colorWithAlphaComponent:kStrength].CGColor, (id)[accent colorWithAlphaComponent:kStrength * 0.35].CGColor,
                        (id)[accent colorWithAlphaComponent:0].CGColor];
    if (animated && gradient.colors) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"colors"];
        fade.fromValue = gradient.presentationLayer ? ((CAGradientLayer *)gradient.presentationLayer).colors : gradient.colors;
        fade.toValue = colors;
        fade.duration = kFade;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [gradient addAnimation:fade forKey:@"accent"];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gradient.colors = colors;
    gradient.locations = @[@0, @0.45, @1];
    [CATransaction commit];
}

@end

void SGRAccentWashPlace(UIView *page) {
    if (!page) return;
    // With the moving background on, the page takes that whole (Settings/SGBackdrop.h) and the light steps aside.
    SGBackdropPlace(page);
    SGRAccentWashView *wash = objc_getAssociatedObject(page, &kWashKey);
    if (SGHidden(SGKeyBackdrop)) {
        [wash removeFromSuperview];
        return;
    }
    if (!wash) {
        wash = [SGRAccentWashView new];
        objc_setAssociatedObject(page, &kWashKey, wash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (wash.superview != page) [page insertSubview:wash atIndex:0];
    else if (page.subviews.firstObject != wash) [page sendSubviewToBack:wash];
    if (!CGRectEqualToRect(wash.frame, page.bounds)) wash.frame = page.bounds;
    // The list under the header is filled black from edge to edge and would cut the light off at its top.
    SGBackdropClearFills(page, wash);
}
