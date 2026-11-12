#import <objc/runtime.h>
#import "SGBackdrop.h"
#import "Core/SGCore.h"
#import "Core/SGPrefs.h"

NSNotificationName const SGBackdropDidChangeNotification = @"SGBackdropDidChangeNotification";

typedef NS_ENUM(NSInteger, SGBackdropStyle) {
    SGBackdropWave = 0,
    SGBackdropAurora,
    SGBackdropPulse,
    SGBackdropTide,
    SGBackdropSpotlights,
    SGBackdropRipples,
    SGBackdropStars,
    SGBackdropRibbons,
    SGBackdropPrism,
    SGBackdropMesh,
    SGBackdropBars,
    SGBackdropStyleCount,
};

static const NSTimeInterval kFade = 1.2, kLongestWait = 2.5;

NSArray<NSString *> *SGBackdropStyleNames(void) {
    return @[@"Wave", @"Aurora", @"Pulse", @"Tide", @"Spotlights", @"Ripples", @"Stars", @"Ribbons", @"Prism", @"Mesh", @"Bars"];
}

static UIColor *fromRGB(NSInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static UIColor *accentColor(void) {
    BOOL redesign = SGRedesignedUIStored();
    NSInteger rgb = SGInt(redesign ? @"spotifyglass.redesign.accent" : @"spotifyglass.accent", redesign ? 0x37F200 : -1);
    return rgb >= 0 && rgb <= 0xFFFFFF ? fromRGB(rgb) : [UIColor colorWithRed:0.11 green:0.84 blue:0.38 alpha:1];
}

static UIColor *currentColor(void) {
    if (SGInt(SGKeyBackdropSource, 0) == 0) {
        NSInteger song = SGInt(SGKeyBackdropSongColor, -1);
        if (song >= 0 && song <= 0xFFFFFF) return fromRGB(song);
    }
    return accentColor();
}

static UIColor *shifted(UIColor *color, CGFloat by) {
    CGFloat h = 0, s = 0, v = 0, a = 1;
    if (![color getHue:&h saturation:&s brightness:&v alpha:&a]) return color;
    h = fmod(h + by + 1, 1);
    return [UIColor colorWithHue:h saturation:s brightness:v alpha:1];
}

static BOOL sameColor(UIColor *one, UIColor *other) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    if (!one || !other || ![one getRed:&r1 green:&g1 blue:&b1 alpha:&a1] || ![other getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) < 0.01 && fabs(g1 - g2) < 0.01 && fabs(b1 - b2) < 0.01;
}

static id cg(UIColor *color, CGFloat alpha) {
    return (id)[color colorWithAlphaComponent:alpha].CGColor;
}

static CABasicAnimation *loop(NSString *keyPath, id from, id to, CFTimeInterval duration, BOOL back) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:keyPath];
    animation.fromValue = from;
    animation.toValue = to;
    animation.duration = duration;
    animation.autoreverses = back;
    animation.repeatCount = HUGE_VALF;
    animation.removedOnCompletion = NO;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:back ? kCAMediaTimingFunctionEaseInEaseOut : kCAMediaTimingFunctionLinear];
    return animation;
}

// A soft round light: the colour at its middle, nothing at its edge.
static CAGradientLayer *blob(UIColor *color, CGFloat alpha, CGFloat side, CGPoint center) {
    CAGradientLayer *layer = [CAGradientLayer layer];
    layer.type = kCAGradientLayerRadial;
    layer.colors = @[cg(color, alpha), cg(color, alpha * 0.35), cg(color, 0)];
    layer.locations = @[@0, @0.5, @1];
    layer.startPoint = CGPointMake(0.5, 0.5);
    layer.endPoint = CGPointMake(1, 1);
    layer.bounds = CGRectMake(0, 0, side, side);
    layer.position = center;
    return layer;
}

static CAKeyframeAnimation *drift(NSArray<NSValue *> *points, CFTimeInterval duration) {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"position"];
    animation.values = [points arrayByAddingObject:points.firstObject];
    animation.calculationMode = kCAAnimationCubicPaced;
    animation.duration = duration;
    animation.repeatCount = HUGE_VALF;
    animation.removedOnCompletion = NO;
    return animation;
}

static NSValue *at(CGSize size, CGFloat x, CGFloat y) {
    return [NSValue valueWithCGPoint:CGPointMake(size.width * x, size.height * y)];
}

static CGPathRef ribbon(CGSize size, CGFloat top, CGFloat height, CGFloat phase) {
    CGMutablePathRef path = CGPathCreateMutable();
    const int steps = 24;
    for (int i = 0; i <= steps; i++) {
        CGFloat x = size.width * i / steps;
        CGFloat y = size.height * top + sin(phase + i * (M_PI * 2 / steps) * 1.5) * height;
        if (i == 0) CGPathMoveToPoint(path, NULL, x, y);
        else CGPathAddLineToPoint(path, NULL, x, y);
    }
    CGPathAddLineToPoint(path, NULL, size.width, size.height);
    CGPathAddLineToPoint(path, NULL, 0, size.height);
    CGPathCloseSubpath(path);
    return path;
}

@interface SGBackdropScene : UIView
@property (nonatomic, readonly) CFTimeInterval period;
- (instancetype)initWithStyle:(SGBackdropStyle)style color:(UIColor *)color;
- (CFTimeInterval)untilLoopEnds;
- (void)beat:(CGFloat)intensity;
@end

@implementation SGBackdropScene {
    SGBackdropStyle _style;
    UIColor *_color;
    CGSize _built;
    CFTimeInterval _began;
    int _meteors;
}

- (instancetype)initWithStyle:(SGBackdropStyle)style color:(UIColor *)color {
    if ((self = [super initWithFrame:CGRectZero])) {
        _style = style;
        _color = color;
        self.backgroundColor = UIColor.blackColor;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rebuild) name:UIApplicationWillEnterForegroundNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (CFTimeInterval)untilLoopEnds {
    if (_period <= 0 || _began <= 0) return 0;
    return _period - fmod(CACurrentMediaTime() - _began, _period);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (CGSizeEqualToSize(_built, self.bounds.size)) return;
    [self rebuild];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) [self rebuild];
}

- (void)rebuild {
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    _built = size;
    _began = CACurrentMediaTime();
    _meteors = 0;
    for (CALayer *layer in [self.layer.sublayers copy]) [layer removeFromSuperlayer];
    BOOL still = UIAccessibilityIsReduceMotionEnabled();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self build:size still:still];
    [CATransaction commit];
}

// A small meteor from the left edge to the right, at a height of its own, a little downhill: a thin trail
// that brightens to a white head with a glow of the colour around it. Gone once it has crossed.
- (void)meteor:(CGFloat)intensity {
    CGSize size = self.bounds.size;
    if (_meteors >= 6 || size.width < 1) return;
    CGFloat length = 70 + arc4random_uniform(70) + 50 * intensity, thick = 1.5 + intensity;
    CALayer *meteor = [CALayer layer];
    meteor.bounds = CGRectMake(0, 0, length, 12);
    CAGradientLayer *trail = [CAGradientLayer layer];
    trail.frame = CGRectMake(0, (12 - thick) / 2, length, thick);
    trail.cornerRadius = thick / 2;
    trail.startPoint = CGPointMake(0, 0.5);
    trail.endPoint = CGPointMake(1, 0.5);
    trail.colors = @[cg(_color, 0), cg(_color, 0.55), cg(UIColor.whiteColor, 0.95)];
    trail.locations = @[@0, @0.7, @1];
    [meteor addSublayer:trail];
    [meteor addSublayer:blob(_color, 0.9, 12, CGPointMake(length - 2, 6))];
    CALayer *head = [CALayer layer];
    head.bounds = CGRectMake(0, 0, thick + 1.5, thick + 1.5);
    head.cornerRadius = (thick + 1.5) / 2;
    head.position = CGPointMake(length - 2, 6);
    head.backgroundColor = UIColor.whiteColor.CGColor;
    [meteor addSublayer:head];

    CGFloat y = size.height * (0.06 + arc4random_uniform(70) / 100.0), fall = size.width * (0.08 + arc4random_uniform(10) / 100.0);
    CGPoint from = CGPointMake(-length, y), to = CGPointMake(size.width + length, y + fall);
    meteor.position = to;
    meteor.opacity = 0;
    meteor.transform = CATransform3DMakeRotation(atan2(fall, size.width + 2 * length), 0, 0, 1);
    CFTimeInterval duration = 0.9 + arc4random_uniform(50) / 100.0;
    _meteors++;
    __weak SGBackdropScene *weakSelf = self;
    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        [meteor removeFromSuperlayer];
        SGBackdropScene *scene = weakSelf;
        if (scene && scene->_meteors > 0) scene->_meteors--;
    }];
    CABasicAnimation *cross = [CABasicAnimation animationWithKeyPath:@"position"];
    cross.fromValue = [NSValue valueWithCGPoint:from];
    cross.toValue = [NSValue valueWithCGPoint:to];
    cross.duration = duration;
    cross.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    CAKeyframeAnimation *shine = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    shine.values = @[@0, @1, @1, @0];
    shine.keyTimes = @[@0, @0.12, @0.8, @1];
    shine.duration = duration;
    [self.layer addSublayer:meteor];
    [meteor addAnimation:cross forKey:@"cross"];
    [meteor addAnimation:shine forKey:@"shine"];
    [CATransaction commit];
}

// The music's beat, as it is felt or reckoned (SGBackdropBeat): the styles with room for it answer.
- (void)beat:(CGFloat)intensity {
    if (!self.window || UIAccessibilityIsReduceMotionEnabled()) return;
    CGSize size = self.bounds.size;
    switch (_style) {
        case SGBackdropStars:
            [self meteor:intensity];
            break;
        case SGBackdropRipples: {
            CAShapeLayer *ring = [CAShapeLayer layer];
            CGFloat side = 120, longer = MAX(size.width, size.height);
            ring.bounds = CGRectMake(0, 0, side, side);
            ring.position = CGPointMake(size.width / 2, size.height / 2);
            ring.path = [UIBezierPath bezierPathWithOvalInRect:ring.bounds].CGPath;
            ring.fillColor = UIColor.clearColor.CGColor;
            ring.strokeColor = (__bridge CGColorRef)cg(_color, 0.5 + 0.4 * intensity);
            ring.lineWidth = 1.5;
            ring.opacity = 0;
            [CATransaction begin];
            [CATransaction setCompletionBlock:^{ [ring removeFromSuperlayer]; }];
            CABasicAnimation *grow = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            grow.fromValue = @0.15;
            grow.toValue = @(longer * 0.9 / side);
            grow.duration = 1.6;
            grow.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @0.9;
            fade.toValue = @0;
            fade.duration = 1.6;
            [self.layer addSublayer:ring];
            [ring addAnimation:grow forKey:@"grow"];
            [ring addAnimation:fade forKey:@"fade"];
            [CATransaction commit];
            break;
        }
        case SGBackdropPulse:
        case SGBackdropMesh:
        case SGBackdropAurora: {
            // A breath of light over the whole scene, gone in half a second.
            CALayer *flash = [CALayer layer];
            flash.frame = self.bounds;
            flash.backgroundColor = (__bridge CGColorRef)cg(_color, 0.1 + 0.1 * intensity);
            flash.opacity = 0;
            [CATransaction begin];
            [CATransaction setCompletionBlock:^{ [flash removeFromSuperlayer]; }];
            CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
            fade.fromValue = @1;
            fade.toValue = @0;
            fade.duration = 0.5;
            [self.layer addSublayer:flash];
            [flash addAnimation:fade forKey:@"fade"];
            [CATransaction commit];
            break;
        }
        default:
            break;
    }
}

- (void)build:(CGSize)size still:(BOOL)still {
    CALayer *root = self.layer;
    UIColor *color = _color;
    CGFloat w = size.width, h = size.height, longer = MAX(w, h);
    CGRect frame = (CGRect){CGPointZero, size};
    switch (_style) {
        case SGBackdropAurora: {
            _period = 18;
            NSArray<UIColor *> *colors = @[color, shifted(color, 0.08), shifted(color, -0.08)];
            NSArray<NSArray<NSValue *> *> *paths = @[
                @[at(size, 0.2, 0.2), at(size, 0.8, 0.35), at(size, 0.5, 0.7), at(size, 0.15, 0.55)],
                @[at(size, 0.85, 0.8), at(size, 0.3, 0.9), at(size, 0.6, 0.4), at(size, 0.9, 0.5)],
                @[at(size, 0.5, 0.1), at(size, 0.1, 0.85), at(size, 0.9, 0.2), at(size, 0.6, 0.95)],
            ];
            for (NSUInteger i = 0; i < 3; i++) {
                CAGradientLayer *light = blob(colors[i], 0.5, longer * (0.9 + 0.2 * i), paths[i].firstObject.CGPointValue);
                [root addSublayer:light];
                if (!still) [light addAnimation:drift(paths[i], 18 + 4 * i) forKey:@"drift"];
            }
            break;
        }
        case SGBackdropPulse: {
            _period = 8;
            CAGradientLayer *light = blob(color, 0.6, longer * 1.5, CGPointMake(w / 2, h * 0.45));
            [root addSublayer:light];
            if (!still) {
                [light addAnimation:loop(@"transform.scale", @0.55, @1.1, 4, YES) forKey:@"scale"];
                [light addAnimation:loop(@"opacity", @0.45, @1, 4, YES) forKey:@"opacity"];
            }
            break;
        }
        case SGBackdropTide: {
            _period = 16;
            for (int i = 0; i < 2; i++) {
                CAGradientLayer *band = [CAGradientLayer layer];
                band.frame = frame;
                band.colors = @[cg(color, 0), cg(i ? shifted(color, 0.06) : color, 0.42), cg(color, 0)];
                band.locations = @[@0.3, @0.5, @0.7];
                [root addSublayer:band];
                if (still) continue;
                NSArray *low = @[@0.75, @1.0, @1.25], *high = @[@(-0.25), @0.0, @0.25];
                [band addAnimation:loop(@"locations", i ? high : low, i ? low : high, 8, YES) forKey:@"tide"];
            }
            break;
        }
        case SGBackdropSpotlights: {
            _period = 16;
            for (int i = 0; i < 2; i++) {
                CAGradientLayer *light = blob(i ? shifted(color, 0.1) : color, 0.55, longer * 0.95, CGPointMake(i ? w : 0, i ? h * 0.8 : h * 0.2));
                [root addSublayer:light];
                if (still) continue;
                CAKeyframeAnimation *orbit = [CAKeyframeAnimation animationWithKeyPath:@"position"];
                CGRect oval = CGRectInset(frame, w * 0.1, h * 0.15);
                UIBezierPath *path = [UIBezierPath bezierPathWithOvalInRect:oval];
                orbit.path = (i ? [path bezierPathByReversingPath] : path).CGPath;
                orbit.calculationMode = kCAAnimationPaced;
                orbit.duration = i ? 20 : 16;
                orbit.repeatCount = HUGE_VALF;
                orbit.removedOnCompletion = NO;
                [light addAnimation:orbit forKey:@"orbit"];
            }
            break;
        }
        case SGBackdropRipples: {
            _period = 6;
            [root addSublayer:blob(color, 0.25, longer, CGPointMake(w / 2, h / 2))];
            CAReplicatorLayer *rings = [CAReplicatorLayer layer];
            rings.frame = frame;
            rings.instanceCount = still ? 1 : 4;
            rings.instanceDelay = 1.5;
            CAShapeLayer *ring = [CAShapeLayer layer];
            CGFloat side = 120;
            ring.bounds = CGRectMake(0, 0, side, side);
            ring.position = CGPointMake(w / 2, h / 2);
            ring.path = [UIBezierPath bezierPathWithOvalInRect:ring.bounds].CGPath;
            ring.fillColor = UIColor.clearColor.CGColor;
            ring.strokeColor = (__bridge CGColorRef)cg(color, 0.6);
            ring.lineWidth = 2;
            ring.opacity = still ? 0.5 : 0;
            [rings addSublayer:ring];
            [root addSublayer:rings];
            if (!still) {
                [ring addAnimation:loop(@"transform.scale", @0.2, @(longer * 1.3 / side), 6, NO) forKey:@"scale"];
                [ring addAnimation:loop(@"opacity", @0.9, @0, 6, NO) forKey:@"opacity"];
            }
            break;
        }
        case SGBackdropStars: {
            // A dim sky of small fixed stars, a few of them breathing; the meteors come with the music (-beat:).
            _period = 3;
            CAGradientLayer *glow = [CAGradientLayer layer];
            glow.frame = frame;
            glow.colors = @[cg(color, 0.16), cg(color, 0), cg(color, 0.1)];
            glow.locations = @[@0, @0.55, @1];
            [root addSublayer:glow];
            for (int i = 0; i < 36; i++) {
                CALayer *star = [CALayer layer];
                CGFloat side = 1 + arc4random_uniform(3) * 0.5;
                star.bounds = CGRectMake(0, 0, side, side);
                star.cornerRadius = side / 2;
                star.position = CGPointMake(arc4random_uniform((uint32_t)w), arc4random_uniform((uint32_t)h));
                star.backgroundColor = UIColor.whiteColor.CGColor;
                star.opacity = 0.25 + arc4random_uniform(40) / 100.0;
                [root addSublayer:star];
                if (still || i % 3) continue;
                CABasicAnimation *twinkle = loop(@"opacity", @(star.opacity), @0.05, 1.5 + arc4random_uniform(20) / 10.0, YES);
                twinkle.beginTime = CACurrentMediaTime() + arc4random_uniform(30) / 10.0;
                [star addAnimation:twinkle forKey:@"twinkle"];
            }
            break;
        }
        case SGBackdropRibbons: {
            _period = 12;
            for (int i = 0; i < 3; i++) {
                CAShapeLayer *wave = [CAShapeLayer layer];
                wave.frame = frame;
                wave.fillColor = (__bridge CGColorRef)cg(shifted(color, 0.05 * (i - 1)), 0.16 + 0.05 * i);
                CGFloat top = 0.3 + 0.2 * i, height = h * (0.06 - 0.01 * i);
                CGPathRef from = ribbon(size, top, height, i), to = ribbon(size, top, height, i + M_PI);
                wave.path = from;
                [root addSublayer:wave];
                if (!still) [wave addAnimation:loop(@"path", (__bridge id)from, (__bridge id)to, 6 + 2 * i, YES) forKey:@"wave"];
                CGPathRelease(from);
                CGPathRelease(to);
            }
            break;
        }
        case SGBackdropPrism: {
            _period = 12;
            CAGradientLayer *cone = [CAGradientLayer layer];
            cone.type = kCAGradientLayerConic;
            CGFloat side = hypot(w, h) * 1.1;
            cone.bounds = CGRectMake(0, 0, side, side);
            cone.position = CGPointMake(w / 2, h / 2);
            cone.startPoint = CGPointMake(0.5, 0.5);
            cone.endPoint = CGPointMake(0.5, 0);
            cone.colors = @[cg(color, 0.5), cg(color, 0), cg(shifted(color, 0.1), 0.4), cg(color, 0), cg(shifted(color, -0.1), 0.4), cg(color, 0), cg(color, 0.5)];
            [root addSublayer:cone];
            if (!still) [cone addAnimation:loop(@"transform.rotation.z", @0, @(M_PI * 2), 24, NO) forKey:@"turn"];
            break;
        }
        case SGBackdropMesh: {
            _period = 10;
            CGFloat shifts[4] = {0, 0.06, -0.06, 0.12};
            CGPoint corners[4] = {{0, 0}, {w, 0}, {0, h}, {w, h}};
            for (int i = 0; i < 4; i++) {
                CAGradientLayer *light = blob(shifted(color, shifts[i]), 0.6, longer * 1.1, corners[i]);
                light.opacity = still ? 0.6 : 0.2;
                [root addSublayer:light];
                if (still) continue;
                CABasicAnimation *breathe = loop(@"opacity", @0.2, @0.95, 5, YES);
                breathe.beginTime = CACurrentMediaTime() + 2.5 * i;
                [light addAnimation:breathe forKey:@"breathe"];
            }
            break;
        }
        case SGBackdropBars: {
            _period = 2.4;
            const NSInteger count = 14;
            CGFloat step = w / count;
            CAReplicatorLayer *bars = [CAReplicatorLayer layer];
            bars.frame = frame;
            bars.instanceCount = count;
            bars.instanceDelay = 0.17;
            bars.instanceTransform = CATransform3DMakeTranslation(step, 0, 0);
            CAGradientLayer *bar = [CAGradientLayer layer];
            bar.colors = @[cg(color, 0.45), cg(color, 0.05)];
            bar.anchorPoint = CGPointMake(0.5, 1);
            bar.bounds = CGRectMake(0, 0, step - 6, h * 0.5);
            bar.position = CGPointMake(step / 2, h);
            bar.cornerRadius = 6;
            bar.transform = CATransform3DMakeScale(1, 0.3, 1);
            [bars addSublayer:bar];
            [root addSublayer:bars];
            if (!still) [bar addAnimation:loop(@"transform.scale.y", @0.25, @1, 1.2, YES) forKey:@"bounce"];
            break;
        }
        default: {
            _period = 14;
            CAGradientLayer *sweep = [CAGradientLayer layer];
            sweep.frame = frame;
            sweep.colors = @[cg(color, 0), cg(color, 0.45), cg(color, 0)];
            sweep.startPoint = CGPointMake(0, 0);
            sweep.endPoint = CGPointMake(1, 1);
            sweep.locations = @[@0, @0.5, @1];
            [root addSublayer:sweep];
            if (!still) [sweep addAnimation:loop(@"locations", @[@(-0.3), @0, @0.3], @[@0.7, @1, @1.3], 7, YES) forKey:@"sweep"];
        }
    }
}

@end

@interface SGBackdropHost : UIView
- (void)colorChanged;
- (void)beat:(CGFloat)intensity;
@end

static NSHashTable<SGBackdropHost *> *sg_hosts;

@implementation SGBackdropHost {
    SGBackdropScene *_scene;
    UIColor *_color;
    NSInteger _style;
    NSUInteger _turn;
}

- (instancetype)init {
    if ((self = [super initWithFrame:UIScreen.mainScreen.bounds])) {
        self.backgroundColor = UIColor.blackColor;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.userInteractionEnabled = NO;
        [self show:currentColor() after:0 fade:0];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(settingsChanged) name:SGBackdropDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)show:(UIColor *)color after:(NSTimeInterval)wait fade:(NSTimeInterval)fade {
    NSUInteger turn = ++_turn;
    _color = color;
    _style = MAX(0, MIN(SGBackdropStyleCount - 1, SGInt(SGKeyBackdropStyle, SGBackdropWave)));
    NSInteger style = _style;
    __weak SGBackdropHost *weakSelf = self;
    void (^swap)(void) = ^{
        SGBackdropHost *host = weakSelf;
        if (!host || turn != host->_turn) return;
        SGBackdropScene *old = host->_scene;
        SGBackdropScene *scene = [[SGBackdropScene alloc] initWithStyle:(SGBackdropStyle)style color:color];
        scene.frame = host.bounds;
        scene.alpha = old ? 0 : 1;
        [host addSubview:scene];
        host->_scene = scene;
        if (!old) return;
        [UIView animateWithDuration:fade delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            scene.alpha = 1;
        } completion:^(BOOL finished) {
            [old removeFromSuperview];
        }];
    };
    if (wait <= 0) swap();
    else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), swap);
}

// The style on screen ends the loop it is on before the new colour comes in over it.
- (void)colorChanged {
    UIColor *color = currentColor();
    if (sameColor(color, _color)) return;
    NSTimeInterval wait = self.window && !UIAccessibilityIsReduceMotionEnabled() ? MIN(kLongestWait, [_scene untilLoopEnds]) : 0;
    [self show:color after:wait fade:kFade];
}

- (void)settingsChanged {
    [self show:currentColor() after:0 fade:0.5];
}

- (void)beat:(CGFloat)intensity {
    if (self.window) [_scene beat:intensity];
}

@end

static SGBackdropHost *newHost(void);

void SGBackdropSync(UITableView *table) {
    if (!table) return;
    BOOL has = [table.backgroundView isKindOfClass:SGBackdropHost.class];
    if (!SGHidden(SGKeyBackdrop)) {
        if (has) table.backgroundView = nil;
        return;
    }
    if (has) {
        // A colour that came in while the page was out of view.
        [(SGBackdropHost *)table.backgroundView colorChanged];
        return;
    }
    // A page with a background of its own, an empty state, keeps it.
    if (table.backgroundView) return;
    table.backgroundView = newHost();
}

static SGBackdropHost *newHost(void) {
    SGBackdropHost *host = [SGBackdropHost new];
    if (!sg_hosts) sg_hosts = [NSHashTable weakObjectsHashTable];
    [sg_hosts addObject:host];
    return host;
}

// Behind a page of Spotify's own: the host at the back of `page`, and the page's own full-size fills above it
// cleared, three levels down, so it shows through. With the switch off the host is taken away.
void SGBackdropPlace(UIView *page) {
    static char key;
    if (!page) return;
    SGBackdropHost *host = objc_getAssociatedObject(page, &key);
    if (!SGHidden(SGKeyBackdrop)) {
        if (host) {
            [host removeFromSuperview];
            objc_setAssociatedObject(page, &key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    if (!host) {
        host = newHost();
        host.autoresizingMask = UIViewAutoresizingNone;
        objc_setAssociatedObject(page, &key, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (host.superview != page) [page insertSubview:host atIndex:0];
    else if (page.subviews.firstObject != host) [page sendSubviewToBack:host];
    if (!CGRectEqualToRect(host.frame, page.bounds)) host.frame = page.bounds;
    [host colorChanged];
    CGFloat area = page.bounds.size.width * page.bounds.size.height;
    if (area < 1) return;
    NSMutableArray<UIView *> *level = [NSMutableArray arrayWithObject:page];
    for (int depth = 0; depth < 4 && level.count; depth++) {
        NSMutableArray<UIView *> *next = [NSMutableArray array];
        for (UIView *view in level) {
            if (view == host || [view isKindOfClass:UIVisualEffectView.class]) continue;
            if (view.bounds.size.width * view.bounds.size.height < area * 0.85) continue;
            if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0.01) view.backgroundColor = UIColor.clearColor;
            [next addObjectsFromArray:view.subviews];
        }
        level = next;
    }
}

// The beat: as Vibrations feels it when it listens, else reckoned at a steady step while a song plays, so
// the styles that answer the music still move with it. Paused, nothing comes.
static BOOL sg_playing;
static CFTimeInterval sg_lastBeat;
static NSTimer *sg_stepper;

static void deal(CGFloat intensity) {
    for (SGBackdropHost *host in sg_hosts.allObjects) [host beat:intensity];
}

void SGBackdropBeat(float intensity) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - sg_lastBeat < 0.16) return;
    sg_lastBeat = now;
    deal(MIN(1, MAX(0, intensity)));
}

void SGBackdropSetPlaying(BOOL playing) {
    sg_playing = playing;
    if (sg_stepper) return;
    sg_stepper = [NSTimer scheduledTimerWithTimeInterval:0.52 repeats:YES block:^(NSTimer *timer) {
        if (!sg_playing || !sg_hosts.count || CACurrentMediaTime() - sg_lastBeat < 1.5) return;
        static int step;
        // Every other step a stronger one, and now and then none: a pulse, not a metronome.
        if (arc4random_uniform(6) == 0) return;
        deal(step++ % 2 ? 0.35 : 0.7);
    }];
    sg_stepper.tolerance = 0.05;
}

void SGBackdropSetSongColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a]) return;
    NSInteger rgb = ((NSInteger)lround(MIN(1, MAX(0, r)) * 255) << 16) | ((NSInteger)lround(MIN(1, MAX(0, g)) * 255) << 8)
        | (NSInteger)lround(MIN(1, MAX(0, b)) * 255);
    if (rgb == SGInt(SGKeyBackdropSongColor, -1)) return;
    SGSetInt(SGKeyBackdropSongColor, rgb);
    for (SGBackdropHost *host in sg_hosts.allObjects) [host colorChanged];
}
