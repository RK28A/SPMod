#import <objc/runtime.h>
#import "Shared/Fusion/Fusion.h"
#import "Settings/SGBackdrop.h"
#import "Core/SGCore.h"
#import "SGRKit.h"
#import "SGRAccent.h"
#import "Settings/SGPageStyle.h"
#import "SGRAccentTint.h"

NSNotificationName const SGRAccentDidChangeNotification = @"SGRAccentDidChangeNotification";

static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};

static NSInteger sg_accent = -1;     // 0xRRGGBB once chosen, read at launch
static NSInteger sg_autoAccent = -1; // 0xRRGGBB when Automatic accent colour reads a field or cover colour

// The redesign's own green until another is picked; Spotify's is a pick of its own, stored as -1.
static const NSInteger kDefaultAccent = 0x37F200;

static NSInteger chosen(void) {
    if (SGHidden(SGRKeyAccentAuto) && sg_autoAccent >= 0) return sg_autoAccent;
    NSInteger rgb = SGInt(SGRKeyAccent, kDefaultAccent);
    return rgb >= 0 && rgb <= 0xFFFFFF ? rgb : -1;
}

static void unpack(uint32_t rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

static void saveRecentAccent(NSInteger rgb) {
    if (rgb < 0) return;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableArray<NSNumber *> *recent = [[defaults arrayForKey:SGRKeyAccentRecent] mutableCopy] ?: [NSMutableArray array];
    [recent removeObject:@(rgb)];
    [recent insertObject:@(rgb) atIndex:0];
    while (recent.count > 5) [recent removeLastObject];
    [defaults setObject:recent forKey:SGRKeyAccentRecent];
}

#pragma mark - what was drawn in an accent before this one

// Spotify makes its green once and keeps the colour it was handed, so what it draws after the accent has
// changed still comes out in the accent of launch, and what is on screen keeps the one it was drawn in. Every
// accent of this launch is remembered, and whatever is found in one of them, or in Spotify's own green, is
// given the one of now: a label's text, a view's fill or tint, a shape layer's fill or stroke, a layer's fill,
// at the brightness it had. Once as the accent changes, cross-fading the window from the old colours to the
// new, and again every little while for what Spotify builds afterwards. Main thread.
static NSMutableArray<NSNumber *> *sg_past;
static NSTimer *sg_sweeper;
static const CGFloat kDimmer = 0xB9 / 215.0;   // the darker of Spotify's two greens beside the lighter
static const NSTimeInterval kSweepEvery = 2, kSweepFade = 0.6;

static void remember(NSInteger rgb) {
    if (rgb < 0) return;
    if (!sg_past) sg_past = [NSMutableArray array];
    if (![sg_past containsObject:@(rgb)]) [sg_past addObject:@(rgb)];
    while (sg_past.count > 24) [sg_past removeObjectAtIndex:0];
}

// How far a colour may be from an accent of before and still be it: tight for a colour set as one, wider
// for the mean of a picture's pixels, which its soft edges pull about.
static CGFloat sg_slack = 0.012;

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) < sg_slack;
}

// YES with the accent of now at the same brightness when (r, g, b) is an accent of before.
static BOOL renewed(CGFloat *r, CGFloat *g, CGFloat *b) {
    if (sg_accent < 0) return NO;
    CGFloat ar, ag, ab;
    unpack((uint32_t)sg_accent, &ar, &ag, &ab);
    for (int dim = 0; dim < 2; dim++) {
        CGFloat factor = dim ? kDimmer : 1;
        if (near(*r, MIN(1, ar * factor)) && near(*g, MIN(1, ag * factor)) && near(*b, MIN(1, ab * factor))) return NO;
    }
    for (NSNumber *past in sg_past) {
        if (past.integerValue == sg_accent) continue;
        CGFloat pr, pg, pb;
        unpack((uint32_t)past.integerValue, &pr, &pg, &pb);
        for (int dim = 0; dim < 2; dim++) {
            CGFloat factor = dim ? kDimmer : 1;
            if (!near(*r, MIN(1, pr * factor)) || !near(*g, MIN(1, pg * factor)) || !near(*b, MIN(1, pb * factor))) continue;
            *r = MIN(1, ar * factor);
            *g = MIN(1, ag * factor);
            *b = MIN(1, ab * factor);
            return YES;
        }
    }
    return NO;
}

static UIColor *renewedColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a < 0.02 || !renewed(&r, &g, &b)) return nil;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

// A new colour for the caller to release, NULL when `color` is not one of before.
static CGColorRef renewedCopy(CGColorRef color) {
    if (!color || CGColorGetNumberOfComponents(color) != 4) return NULL;
    CGColorSpaceRef space = CGColorGetColorSpace(color);
    if (!space || CGColorSpaceGetModel(space) != kCGColorSpaceModelRGB) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (c[3] < 0.02 || !renewed(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(space, out);
}

// A small picture with its colour drawn in, a glyph Spotify made once in the accent it was handed: the pin
// of a pinned playlist, the device a song plays on. One whose pixels come to an accent of before is drawn
// again in the accent of now, through its own shape. Covers are far from one colour and never come to one.
static const CGFloat kGlyphLimit = 64;
static char kSeenKey;

// A picture's pixels come to one colour. NO for a picture that fills its square, or is no glyph's size.
static BOOL meanOf(CGImageRef picture, CGFloat *r, CGFloat *g, CGFloat *b) {
    if (!picture || CGImageGetWidth(picture) > 400 || CGImageGetHeight(picture) > 400) return NO;
    uint8_t pixel[4] = {0, 0, 0, 0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = space ? CGBitmapContextCreate(pixel, 1, 1, 8, 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) return NO;
    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), picture);
    CGContextRelease(context);
    // A glyph leaves most of its square empty; a cover fills it, and is left alone whatever its colour.
    if (pixel[3] < 8 || pixel[3] > 235) return NO;
    *r = pixel[0] / (CGFloat)pixel[3];
    *g = pixel[1] / (CGFloat)pixel[3];
    *b = pixel[2] / (CGFloat)pixel[3];
    return YES;
}

static BOOL glyphOfBefore(CGImageRef picture) {
    CGFloat r = 0, g = 0, b = 0;
    if (!meanOf(picture, &r, &g, &b)) return NO;
    sg_slack = 0.07;
    BOOL was = renewed(&r, &g, &b);
    sg_slack = 0.012;
    return was;
}

static CGFloat hueOf(CGFloat r, CGFloat g, CGFloat b, CGFloat *saturation) {
    CGFloat high = MAX(r, MAX(g, b)), low = MIN(r, MIN(g, b)), span = high - low;
    *saturation = high > 0 ? span / high : 0;
    if (span < 0.001) return 0;
    CGFloat hue = (high == r ? fmod((g - b) / span, 6) : high == g ? (b - r) / span + 2 : (r - g) / span + 4) / 6;
    return hue < 0 ? hue + 1 : hue;
}

static BOOL hueOfRGB(NSInteger rgb, CGFloat hue) {
    CGFloat r, g, b, saturation = 0;
    if (rgb < 0) return NO;
    unpack((uint32_t)rgb, &r, &g, &b);
    CGFloat other = hueOf(r, g, b, &saturation), apart = fabs(other - hue);
    return saturation > 0.15 && MIN(apart, 1 - apart) < 0.035;
}

// The same shape filled with `color`, for the caller to release.
static CGImageRef recolored(CGImageRef picture, UIColor *color) {
    size_t width = CGImageGetWidth(picture), height = CGImageGetHeight(picture);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = space ? CGBitmapContextCreate(NULL, width, height, 8, 0, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) return NULL;
    CGRect whole = CGRectMake(0, 0, width, height);
    CGContextDrawImage(context, whole, picture);
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, whole);
    CGImageRef made = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return made;
}

// Each picture is looked at once an accent: what a view or layer was last seen holding, and under which
// accent, is kept on it.
static BOOL seenBefore(id holder, const void *picture) {
    unsigned long long now = (unsigned long long)(uintptr_t)picture ^ ((unsigned long long)sg_accent << 40);
    NSNumber *seen = objc_getAssociatedObject(holder, &kSeenKey);
    if (seen && seen.unsignedLongLongValue == now) return YES;
    objc_setAssociatedObject(holder, &kSeenKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return NO;
}

static void sweepPicture(UIImageView *view) {
    UIImage *image = view.image;
    CGSize size = view.bounds.size;
    if (!image || size.width > kGlyphLimit || size.height > kGlyphLimit || image.renderingMode == UIImageRenderingModeAlwaysTemplate) return;
    if (seenBefore(view, (__bridge const void *)image) || image.isSymbolImage || !glyphOfBefore(image.CGImage)) return;
    UIImage *shape = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    view.image = shape;
    view.tintColor = SGRAccentColor();
    seenBefore(view, (__bridge const void *)shape);
}

static void sweepContents(CALayer *layer) {
    id contents = layer.contents;
    CGSize size = layer.bounds.size;
    if (!contents || size.width > kGlyphLimit || size.height > kGlyphLimit || [layer.delegate isKindOfClass:UIImageView.class]) return;
    if (CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) return;
    CGImageRef picture = (__bridge CGImageRef)contents;
    if (seenBefore(layer, picture) || !glyphOfBefore(picture)) return;
    UIColor *accent = SGRAccentColor();
    CGImageRef made = accent ? recolored(picture, accent) : NULL;
    if (!made) return;
    layer.contents = (__bridge id)made;
    seenBefore(layer, made);
    CGImageRelease(made);
}

static void sweepLayer(CALayer *layer, int depth) {
    sweepContents(layer);
    if ([layer isKindOfClass:CAShapeLayer.class]) {
        CAShapeLayer *shape = (CAShapeLayer *)layer;
        CGColorRef fill = renewedCopy(shape.fillColor);
        if (fill) {
            shape.fillColor = fill;
            CGColorRelease(fill);
        }
        CGColorRef stroke = renewedCopy(shape.strokeColor);
        if (stroke) {
            shape.strokeColor = stroke;
            CGColorRelease(stroke);
        }
    }
    CGColorRef back = renewedCopy(layer.backgroundColor);
    if (back) {
        layer.backgroundColor = back;
        CGColorRelease(back);
    }
    if (depth > 12) return;
    for (CALayer *sub in [layer.sublayers copy]) {
        // A view's own layer is reached through the view.
        if ([sub.delegate isKindOfClass:UIView.class]) continue;
        sweepLayer(sub, depth + 1);
    }
}

static void sweepView(UIView *view, int depth) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        UIColor *text = label.text.length ? renewedColor(label.textColor) : nil;
        if (text) label.textColor = text;
    }
    UIColor *tint = renewedColor(view.tintColor);
    if (tint) view.tintColor = tint;
    if ([view isKindOfClass:UIImageView.class]) sweepPicture((UIImageView *)view);
    sweepLayer(view.layer, 0);
    if (depth > 60) return;
    for (UIView *sub in [view.subviews copy]) sweepView(sub, depth + 1);
}

static void sweep(BOOL faded) {
    if (!sg_past.count || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;
            if (faded && !UIAccessibilityIsReduceMotionEnabled()) {
                [UIView transitionWithView:window duration:kSweepFade
                                   options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                                animations:^{ sweepView(window, 0); } completion:nil];
            } else {
                sweepView(window, 0);
            }
        }
    }
}

// The accent became `rgb`: what was drawn in the one before fades to it.
// The settings' moving background, and the same behind Home and the library, take the accent itself.
static void handBackdrop(void) {
    UIColor *accent = SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    SGBackdropSetSongColor(accent);
}

// From launch on, not only once the accent has changed: Spotify's own greens are accents of before too, and
// what it draws in them without making the colour, a picture with the green in it, is only caught here.
static void keepSweeping(void) {
    remember(kDefaultAccent);
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) remember(kGreens[i]);
    if (sg_sweeper) return;
    sg_sweeper = [NSTimer scheduledTimerWithTimeInterval:kSweepEvery repeats:YES block:^(NSTimer *timer) { sweep(NO); }];
    sg_sweeper.tolerance = 0.5;
}

static void turned(NSInteger before) {
    handBackdrop();
    remember(before);
    dispatch_async(dispatch_get_main_queue(), ^{
        keepSweeping();
        sweep(YES);
    });
}

// Automatic has two sources, the page's cover and the song's, and each used to take the accent from the
// other as it came in: a page opened while a song played went to its colour, then back at the next track.
// The song playing is the one followed; a page's colour only counts until a song has given one.
static BOOL sg_songGave;
static NSString *const kAutoLast = @"spotifyglass.redesign.accent.autoLast";

static void applyAutoColor(UIColor *source, BOOL song) {
    if (!SGHidden(SGRKeyAccentAuto) || !source) return;
    if (song) sg_songGave = YES;
    else if (sg_songGave) return;
    CGFloat h = 0, s = 0, v = 0, a = 1;
    if (![source getHue:&h saturation:&s brightness:&v alpha:&a] || s < 0.12) return;
    UIColor *bright = [UIColor colorWithHue:h saturation:MIN(0.85, MAX(0.48, s * 1.35)) brightness:MAX(0.88, v) alpha:1];
    CGFloat r = 0, g = 0, b = 0;
    [bright getRed:&r green:&g blue:&b alpha:&a];
    NSInteger rgb = ((NSInteger)lround(r * 255) << 16) | ((NSInteger)lround(g * 255) << 8) | (NSInteger)lround(b * 255);
    if (rgb == sg_autoAccent) return;
    NSInteger before = sg_accent;
    sg_autoAccent = rgb;
    sg_accent = rgb;
    SGSetInt(kAutoLast, rgb);
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAccentDidChangeNotification object:nil];
    turned(before);
}

UIColor *SGRAccentColor(void) {
    NSInteger rgb = chosen();
    if (rgb < 0) return nil;
    CGFloat r, g, b;
    unpack((uint32_t)rgb, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

NSString *SGRAccentLabel(void) {
    if (SGHidden(SGRKeyAccentAuto)) return @"Automatic";
    NSInteger rgb = chosen();
    return rgb < 0 ? @"Spotify green" : [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

#pragma mark - picker

@interface SGRAccentPicker : NSObject <UIColorPickerViewControllerDelegate>
@end

@implementation SGRAccentPicker

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [picker.selectedColor getRed:&r green:&g blue:&b alpha:&a];
    uint32_t rgb = ((uint32_t)lround(MIN(1, MAX(0, r)) * 255) << 16)
                 | ((uint32_t)lround(MIN(1, MAX(0, g)) * 255) << 8)
                 | (uint32_t)lround(MIN(1, MAX(0, b)) * 255);
    saveRecentAccent((NSInteger)rgb);
    SGRSetAccent((NSInteger)rgb);
}

@end

void SGRSetAccent(NSInteger rgb) {
    // A colour asked for by hand is the one wanted: Automatic steps aside.
    SGSetEnabled(SGRKeyAccentAuto, NO);
    sg_autoAccent = -1;
    SGSetInt(SGRKeyAccent, rgb);
    NSInteger now = chosen(), before = sg_accent;
    if (now >= 0) sg_accent = now;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRAccentDidChangeNotification object:nil];
    if (now >= 0 && now != before) turned(before);
}

void SGRPickAccent(void) {
    static SGRAccentPicker *delegate;
    if (!delegate) delegate = [SGRAccentPicker new];
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.supportsAlpha = NO;
    picker.selectedColor = SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    picker.delegate = delegate;
    // Asked for from a sheet's button, the sheet is still on its way out: the picker goes up from what is
    // under it, a turn of the run loop later, and not from a controller that is leaving.
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = SGTopController();
        while (top && (top.isBeingDismissed || [top isKindOfClass:UIAlertController.class])) top = top.presentingViewController;
        if (!top || top.presentedViewController) return;
        [top presentViewController:picker animated:YES completion:nil];
    });
}

// The accent Spotify's green first became: what it makes once and keeps (a SwiftUI page's colours) stays in
// this one however the accent moves afterwards.
static NSInteger sg_handed = -1;

UIColor *SGRAccentHanded(void) {
    if (sg_handed < 0) return nil;
    CGFloat r, g, b;
    unpack((uint32_t)sg_handed, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}

static BOOL swap(CGFloat *r, CGFloat *g, CGFloat *b) {
    for (size_t i = 0; i < sizeof(kGreens) / sizeof(kGreens[0]); i++) {
        CGFloat gr, gg, gb;
        unpack(kGreens[i], &gr, &gg, &gb);
        if (fabs(*r - gr) > 0.01 || fabs(*g - gg) > 0.01 || fabs(*b - gb) > 0.01) continue;
        CGFloat ar, ag, ab;
        if (sg_accent < 0) return NO;
        if (sg_handed < 0) sg_handed = sg_accent;
        unpack((uint32_t)sg_accent, &ar, &ag, &ab);
        CGFloat factor = MAX(gr, MAX(gg, gb)) / (0xD7 / 255.0);
        *r = MIN(1, ar * factor);
        *g = MIN(1, ag * factor);
        *b = MIN(1, ab * factor);
        return YES;
    }
    return NO;
}

%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    swap(&r, &g, &b);
    return %orig(r, g, b, a);
}
%end

// Spotify keeps the colour it was handed when it made its green, the accent of that moment, and sets it
// again long after the accent has moved on (a button as it is pressed, a label as its row is reused). A tint
// or a text colour that is an accent of before, or Spotify's own green from a maker the hooks above never
// saw, becomes the accent of now as it is set, so the old one is never drawn.
// The colour handed back is the same object for the same alpha, so a view set to it twice is set to what it
// already has, and one that sets the old colour on every pass is counted and left alone (SGRAccentKeepsAsking).
static UIColor *swappedColor(UIColor *color) {
    static NSMutableDictionary<NSNumber *, UIColor *> *made;
    static NSInteger madeFor = -1;
    CGFloat r = 0, g = 0, b = 0, a = 0, saturation = 0;
    if (sg_accent < 0 || !sg_past.count || !color || ![color getRed:&r green:&g blue:&b alpha:&a]) return color;
    // White, grey and black are the interface's own, whatever accent was once picked.
    hueOf(r, g, b, &saturation);
    if (saturation < 0.25) return color;
    sg_slack = 0.03;
    BOOL was = renewed(&r, &g, &b);
    sg_slack = 0.012;
    if (!was) return color;
    if (madeFor != sg_accent || !made) {
        made = [NSMutableDictionary dictionary];
        madeFor = sg_accent;
    }
    NSNumber *key = @((int)lround(a * 255));
    UIColor *now = made[key];
    if (!now) {
        now = [UIColor colorWithRed:r green:g blue:b alpha:a];
        made[key] = now;
    }
    return now;
}

// The same for a small picture with the colour drawn in. What a picture was found to be is kept on it with
// the accent it was judged under.
BOOL SGRAccentPictureIsStale(UIImage *image) {
    static char kJudgedKey;
    if (sg_accent < 0 || !image) return NO;
    NSNumber *fine = objc_getAssociatedObject(image, &kJudgedKey);
    if (fine && fine.integerValue == sg_accent) return NO;
    CGFloat r = 0, g = 0, b = 0, saturation = 0;
    if (meanOf(image.CGImage, &r, &g, &b)) {
        sg_slack = 0.07;
        CGFloat mr = r, mg = g, mb = b;
        BOOL was = renewed(&mr, &mg, &mb);
        sg_slack = 0.012;
        if (was) return YES;
        // A glyph with white or black drawn into it (a download on its way: an arrow in a disc) comes to a
        // paler or darker colour than the one it was drawn in, of the same hue. The hues Spotify holds are
        // few: its own green, and the accent its green first became.
        CGFloat hue = hueOf(r, g, b, &saturation);
        if (saturation > 0.3 && !hueOfRGB(sg_accent, hue)) {
            if (hueOfRGB(sg_handed, hue) || hueOfRGB(kDefaultAccent, hue) || hueOfRGB(kGreens[0], hue)) return YES;
        }
    }
    objc_setAssociatedObject(image, &kJudgedKey, @(sg_accent), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return NO;
}

%hook UIView
- (void)setTintColor:(UIColor *)color {
    UIColor *now = swappedColor(color);
    if (now != color && self.tintColor == now && SGRAccentKeepsAsking(self, @"tint")) now = color;
    %orig(now);
}
%end

%hook UILabel
- (void)setTextColor:(UIColor *)color {
    UIColor *now = swappedColor(color);
    if (now != color && self.textColor == now && SGRAccentKeepsAsking(self, @"text colour")) now = color;
    %orig(now);
}
%end

// A glyph's picture changes without its row being laid out again (a download starting): it is looked at as
// it comes in, and the view is handed the right one in its place, once. Handing it Spotify's and then the
// right one made two changes of every one of Spotify's, and a button that sets its picture on every pass and
// lays out again when its picture changes never stopped: the playlist page, frozen behind its curtain.
%hook UIImageView
- (void)setImage:(UIImage *)image {
    UIImage *drawn = SGRAccentGlyphFor(self, image);
    %orig(drawn);
    SGRAccentGlyphSet(self, drawn != image ? drawn : nil);
}
%end

static CGColorRef swappedCopy(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID() || CGColorGetNumberOfComponents(color) != 4) return NULL;
    const CGFloat *c = CGColorGetComponents(color);
    CGFloat r = c[0], g = c[1], b = c[2];
    if (!swap(&r, &g, &b)) return NULL;
    CGFloat out[] = {r, g, b, c[3]};
    return CGColorCreate(CGColorGetColorSpace(color), out);
}

static id swappedValue(id value) {
    CGColorRef swapped = swappedCopy((__bridge CGColorRef)value);
    if (!swapped) return value;
    id boxed = (__bridge_transfer id)swapped;
    return boxed;
}

%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
- (void)setStrokeColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    CGColorRef swapped = swappedCopy(color);
    CGColorRef used = swapped ?: color;
    %orig(used);
    if (swapped) CGColorRelease(swapped);
}
%end

%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = swappedValue(value);
    %orig(used);
}
%end

%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    NSMutableArray *mapped = nil;
    for (NSUInteger i = 0; i < values.count; i++) {
        id swapped = swappedValue(values[i]);
        if (swapped == values[i] && !mapped) continue;
        if (!mapped) mapped = [values mutableCopy];
        mapped[i] = swapped;
    }
    NSArray *used = mapped ?: values;
    %orig(used);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    // Automatic starts from the colour it last had, not from the stored accent until a cover comes in.
    if (SGHidden(SGRKeyAccentAuto)) {
        NSInteger last = SGInt(kAutoLast, -1);
        if (last >= 0 && last <= 0xFFFFFF) sg_autoAccent = last;
    }
    sg_accent = chosen();
    if (SGHidden(SGRKeyAccentAuto)) {
        [NSNotificationCenter.defaultCenter addObserverForName:SGRFieldColorDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UIColor *color = note.userInfo[@"color"];
            if (color) applyAutoColor(color, NO);
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UIImage *image = note.userInfo[@"image"];
            if (!image) return;
            SGRPaletteRequest req = {0};
            [SGRPalette paletteForImage:image request:req completion:^(SGRPalette *palette) {
                if (palette.fieldColor) applyAutoColor(palette.fieldColor, YES);
            }];
        }];
    }
    if (sg_accent >= 0 || SGHidden(SGRKeyAccentAuto)) %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        handBackdrop();
        if (sg_accent >= 0 || SGHidden(SGRKeyAccentAuto)) keepSweeping();
    });
    SGFusionAccent = ^UIColor *{ return SGRAccentColor(); };
}
