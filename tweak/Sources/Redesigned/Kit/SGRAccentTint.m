#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRAccent.h"
#import "SGRAccentTint.h"

static char kChromaticKey, kTemplateKey, kMadeKey;

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
    if (!one || !other || ![one getRed:&r1 green:&g1 blue:&b1 alpha:&a1] || ![other getRed:&r2 green:&g2 blue:&b2 alpha:&a2]) return NO;
    return fabs(r1 - r2) < 0.01 && fabs(g1 - g2) < 0.01 && fabs(b1 - b2) < 0.01;
}

// A glyph is small; a cover is a picture, whatever its colour, and is never drawn again in one colour.
static const CGFloat kGlyphSide = 32;

// Whether the picture is drawn in Spotify's green: its pixels averaged into one. Kept on the image, read once.
static BOOL imageIsGreen(UIImage *image) {
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
            if (pixel[3] > 8) {
                CGFloat r = pixel[0] / (CGFloat)pixel[3], g = pixel[1] / (CGFloat)pixel[3], b = pixel[2] / (CGFloat)pixel[3];
                result = g > 0.45 && g > r * 1.45 && g > b * 1.3;
            }
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

// A glyph drawn with a tint takes the accent on the view the colour comes from: the highest one under
// `root` whose tint is still that colour. Spotify setting its own colour there again, white once the device
// stops playing, then replaces the accent the way it replaced its green.
static void tintGlyph(UIImageView *glyph, UIView *root, UIColor *accent) {
    UIImage *image = glyph.image;
    if (!image) return;
    UIImage *made = objc_getAssociatedObject(glyph, &kMadeKey);
    if (made && made != image) {
        objc_setAssociatedObject(glyph, &kMadeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glyph.tintColor = nil;
    }
    UIButton *button = [glyph.superview isKindOfClass:UIButton.class] ? (UIButton *)glyph.superview : nil;
    BOOL drawnWithTint = image.renderingMode == UIImageRenderingModeAlwaysTemplate
        || (image.renderingMode == UIImageRenderingModeAutomatic && (image.isSymbolImage || button.buttonType == UIButtonTypeSystem));
    if (drawnWithTint) {
        for (int pass = 0; pass < 3; pass++) {
            UIColor *tint = glyph.tintColor;
            if (!chromatic(tint) || sameColor(tint, accent)) return;
            UIView *owner = glyph;
            while (owner != root && owner.superview && sameColor(owner.superview.tintColor, tint)) owner = owner.superview;
            owner.tintColor = accent;
        }
        return;
    }
    // A small picture with Spotify's green drawn in becomes a template of itself, so the accent can draw it.
    CGSize size = glyph.bounds.size;
    if (MAX(size.width, size.height) > kGlyphSide || MAX(image.size.width, image.size.height) > kGlyphSide) return;
    if (!imageIsGreen(image)) return;
    made = templateOf(image);
    glyph.image = made;
    glyph.tintColor = accent;
    objc_setAssociatedObject(glyph, &kMadeKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void SGRAccentRetintGlyph(UIImageView *glyph) {
    UIColor *accent = SGRAccentColor();
    if (glyph && accent) tintGlyph(glyph, glyph, accent);
}

void SGRAccentRetint(UIView *root) {
    UIColor *accent = SGRAccentColor();
    if (!root || !accent) return;
    SGForEachView(root, ^(UIView *view) {
        if ([view isKindOfClass:UIImageView.class]) {
            tintGlyph((UIImageView *)view, root, accent);
        } else if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            if (chromatic(label.textColor) && !sameColor(label.textColor, accent)) label.textColor = accent;
        }
    });
}
