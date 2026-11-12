// The glyphs of the shuffle modes (Fusion.h), drawn here so they scale to any size and take any tint.
// Fusion's is a pair of drop earrings, an orb under a small open hoop each, leaning apart: two that are worn
// to become one. No Shuffle and Smart Shuffle are the system's shuffle arrows with a mark at their corner.
#import "Fusion.h"

static UIImage *badged(NSString *badge, CGFloat side) {
    UIImageSymbolConfiguration *large = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.72 weight:UIImageSymbolWeightSemibold];
    UIImageSymbolConfiguration *small = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.36 weight:UIImageSymbolWeightBold];
    UIImage *arrows = [UIImage systemImageNamed:@"shuffle" withConfiguration:large];
    UIImage *mark = [UIImage systemImageNamed:badge withConfiguration:small];
    CGSize size = CGSizeMake(side, side);
    UIImage *drawn = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGSize whole = arrows.size;
        [arrows drawInRect:CGRectMake((side - whole.width) / 2 - side * 0.05, (side - whole.height) / 2 - side * 0.04, whole.width, whole.height)];
        // The corner the mark sits in is cut out of the arrows first, so the two do not run together.
        CGSize corner = mark.size;
        CGRect spot = CGRectMake(side - corner.width - side * 0.01, side - corner.height - side * 0.02, corner.width, corner.height);
        CGContextSetBlendMode(context.CGContext, kCGBlendModeClear);
        CGContextFillEllipseInRect(context.CGContext, CGRectInset(spot, -side * 0.05, -side * 0.05));
        CGContextSetBlendMode(context.CGContext, kCGBlendModeNormal);
        [mark drawInRect:spot];
    }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void earring(CGContextRef context, CGFloat unit, CGFloat x, CGFloat lean) {
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, x * unit, 4.6 * unit);
    CGContextRotateCTM(context, lean);
    CGContextSetLineWidth(context, 1.7 * unit);
    CGContextSetLineCap(context, kCGLineCapRound);
    // The hoop, open at its outer side, then the stem down to the orb.
    CGContextAddArc(context, 0, 0, 2.3 * unit, M_PI * 0.15, M_PI * 1.75, 0);
    CGContextStrokePath(context);
    CGContextMoveToPoint(context, 0, 2.3 * unit);
    CGContextAddLineToPoint(context, 0, 6.2 * unit);
    CGContextStrokePath(context);
    CGContextFillEllipseInRect(context, CGRectMake(-4.3 * unit, 6.4 * unit, 8.6 * unit, 8.6 * unit));
    // A glint on the orb.
    CGContextSetBlendMode(context, kCGBlendModeClear);
    CGContextSetLineWidth(context, 1.3 * unit);
    CGContextAddArc(context, 0, 10.7 * unit, 2.6 * unit, M_PI * 1.08, M_PI * 1.42, 0);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

static UIImage *earrings(CGFloat side) {
    CGSize size = CGSizeMake(side, side);
    UIImage *drawn = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat unit = side / 24;
        [UIColor.blackColor set];
        earring(context.CGContext, unit, 7.2, 0.16);
        earring(context.CGContext, unit, 16.8, -0.16);
    }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *SGFusionIcon(SGFusionGlyph glyph, CGFloat side) {
    static NSCache<NSString *, UIImage *> *made;
    if (!made) made = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%ld %.1f", (long)glyph, side];
    UIImage *image = [made objectForKey:key];
    if (image) return image;
    switch (glyph) {
        case SGFusionGlyphNoShuffle: image = badged(@"xmark", side); break;
        case SGFusionGlyphSmart: image = badged(@"sparkle", side); break;
        case SGFusionGlyphFusion: image = earrings(side); break;
        default: {
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.72 weight:UIImageSymbolWeightSemibold];
            image = [[UIImage systemImageNamed:@"shuffle" withConfiguration:configuration] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
    }
    if (image) [made setObject:image forKey:key];
    return image;
}
