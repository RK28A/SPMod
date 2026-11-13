#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGRAccent.h"
#import "SGRAccentTint.h"

static char kTemplateKey, kMadeKey;

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

// A view whose owner sets the old colour or picture back on every pass, and lays out again when it finds
// another, turns "set it right as it is set" into a loop that never ends: the playlist page froze black on
// one. A view handed the same thing back kTurns times in a second is left as its owner sets it, and said.
static const int kTurns = 200;

@interface SGRTurns : NSObject {
@public
    CFTimeInterval since;
    int count;
    BOOL left;
}
@end

@implementation SGRTurns
@end

BOOL SGRAccentKeepsAsking(UIView *view, NSString *what) {
    static char kTurnsKey;
    SGRTurns *turns = objc_getAssociatedObject(view, &kTurnsKey);
    CFTimeInterval now = CACurrentMediaTime();
    if (!turns) {
        turns = [SGRTurns new];
        turns->since = now;
        objc_setAssociatedObject(view, &kTurnsKey, turns, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (turns->left) return YES;
    if (now - turns->since > 1) {
        turns->since = now;
        turns->count = 0;
    }
    if (++turns->count <= kTurns) return NO;
    turns->left = YES;
    SGLog(@"accent: %@ in %@ was handed its old %@ back %d times in a second, left as its owner sets it",
          NSStringFromClass(view.class), NSStringFromClass(view.superview.class), what, kTurns);
    return YES;
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
    SGRAccentGlyphSet(glyph, nil);
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
    UIImage *drawn = SGRAccentGlyphFor(glyph, image);
    if (drawn == image) return;
    glyph.image = drawn;
    SGRAccentGlyphSet(glyph, drawn);
}

// What an image view is to hold when it is handed `image`: the image, or for a small picture drawn in an
// accent of before (or in Spotify's green) a template of it, the same one every time, so the view never goes
// from one to the other and back. Any other colour is the picture's own and stays; a cover is no glyph.
UIImage *SGRAccentGlyphFor(UIImageView *glyph, UIImage *image) {
    if (!image || image.renderingMode == UIImageRenderingModeAlwaysTemplate || image.isSymbolImage) return image;
    if (MAX(image.size.width, image.size.height) > kGlyphSide) return image;
    CGSize size = glyph.bounds.size;
    if (MAX(size.width, size.height) > kGlyphSide || !SGRAccentPictureIsStale(image)) return image;
    UIImage *made = templateOf(image);
    if (glyph.image == made && SGRAccentKeepsAsking(glyph, @"picture")) return image;
    return made;
}

// After the view has taken it: `made` is the template it now holds, drawn in the accent; nil when it was
// handed anything else, and the tint a template of before left on it goes.
void SGRAccentGlyphSet(UIImageView *glyph, UIImage *made) {
    UIImage *before = objc_getAssociatedObject(glyph, &kMadeKey);
    if (!made) {
        if (!before || glyph.image == before) return;
        objc_setAssociatedObject(glyph, &kMadeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        glyph.tintColor = nil;
        return;
    }
    if (before != made) objc_setAssociatedObject(glyph, &kMadeKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIColor *accent = SGRAccentColor();
    if (accent && !sameColor(glyph.tintColor, accent)) glyph.tintColor = accent;
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
