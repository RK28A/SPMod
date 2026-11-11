#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "NowPlayingBar.h"

static char kChromaticKey, kTemplateKey, kTintedImageKey;

static BOOL chromaticRGB(CGFloat r, CGFloat g, CGFloat b) {
    CGFloat high = MAX(r, MAX(g, b)), low = MIN(r, MIN(g, b));
    return high > 0.2 && (high - low) / high > 0.3;
}

static BOOL chromatic(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a < 0.05) return NO;
    return chromaticRGB(r, g, b);
}

static BOOL sameColor(UIColor *one, UIColor *other) {
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 0, r2 = 0, g2 = 0, b2 = 0, a2 = 0;
    if (![one getRed:&r1 green:&g1 blue:&b1 alpha:&a1] || ![other getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) < 0.01 && fabs(g1 - g2) < 0.01 && fabs(b1 - b2) < 0.01;
}

static BOOL imageIsChromatic(UIImage *image) {
    NSNumber *known = objc_getAssociatedObject(image, &kChromaticKey);
    if (known) return known.boolValue;
    BOOL result = NO;
    CGImageRef pixels = image.CGImage;
    if (pixels) {
        uint8_t pixel[4] = {0, 0, 0, 0};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = space ? CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
        if (space) CGColorSpaceRelease(space);
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), pixels);
            CGContextRelease(context);
            if (pixel[3] > 8) result = chromaticRGB(pixel[0] / (CGFloat)pixel[3], pixel[1] / (CGFloat)pixel[3], pixel[2] / (CGFloat)pixel[3]);
        }
    }
    objc_setAssociatedObject(image, &kChromaticKey, @(result), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

static UIImage *templateOf(UIImage *image) {
    UIImage *made = objc_getAssociatedObject(image, &kTemplateKey);
    if (made) return made;
    made = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    objc_setAssociatedObject(image, &kTemplateKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return made;
}

static void tintGlyph(UIImageView *glyph, UIColor *accent) {
    UIImage *image = glyph.image;
    if (!image) return;
    UIImage *tinted = objc_getAssociatedObject(glyph, &kTintedImageKey);
    if (tinted && tinted != image) {
        objc_setAssociatedObject(glyph, &kTintedImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glyph.tintColor = nil;
    }
    UIButton *button = [glyph.superview isKindOfClass:UIButton.class] ? (UIButton *)glyph.superview : nil;
    BOOL drawnWithTint = image.renderingMode == UIImageRenderingModeAlwaysTemplate
        || (image.renderingMode == UIImageRenderingModeAutomatic && (image.isSymbolImage || button.buttonType == UIButtonTypeSystem));
    if (drawnWithTint) {
        if (!chromatic(glyph.tintColor) || sameColor(glyph.tintColor, accent)) return;
        glyph.tintColor = accent;
        objc_setAssociatedObject(glyph, &kTintedImageKey, image, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!imageIsChromatic(image)) return;
    UIImage *made = templateOf(image);
    glyph.image = made;
    glyph.tintColor = accent;
    objc_setAssociatedObject(glyph, &kTintedImageKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void tintConnect(UIView *bar) {
    UIColor *accent = SGRAccentColor();
    if (!bar || !accent) return;
    SGForEachView(bar, ^(UIView *host) {
        NSString *name = NSStringFromClass(host.class);
        if (![name containsString:@"ConnectStateView"] && ![name containsString:@"ConnectButtonView"]) return;
        SGForEachView(host, ^(UIView *view) {
            if ([view isKindOfClass:UIImageView.class]) {
                tintGlyph((UIImageView *)view, accent);
            } else if ([view isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)view;
                if (chromatic(label.textColor) && !sameColor(label.textColor, accent)) label.textColor = accent;
            }
        });
    });
}

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    tintConnect(((UIViewController *)self).view);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"]);
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        tintConnect(sgr_nowPlayingRoot);
    }];
}
