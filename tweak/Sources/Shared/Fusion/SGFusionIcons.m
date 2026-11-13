// The glyphs of the shuffle modes and of Playlist Fusion (Fusion.h), drawn here so they scale to any size
// and take any tint. Fusion Shuffle has two drawings to choose from in its settings: the shuffle arrows with
// a pair of drop earrings at their corner, where No Shuffle has its cross, and the pair hanging from the
// arrows. Playlist Fusion's is two rings running into one orb. No Shuffle and Smart Shuffle are the system's
// shuffle arrows with a mark at their corner. The drawn ones are laid out on a grid of 24.
#import "Fusion.h"
#import "Core/SGCore.h"

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

static UIImage *onGrid(CGFloat side, void (^draw)(CGContextRef context)) {
    UIImage *drawn = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)] imageWithActions:^(UIGraphicsImageRendererContext *renderer) {
        CGContextRef context = renderer.CGContext;
        CGContextScaleCTM(context, side / 24, side / 24);
        CGContextSetLineCap(context, kCGLineCapRound);
        CGContextSetLineJoin(context, kCGLineJoinRound);
        [UIColor.blackColor set];
        draw(context);
    }];
    return [drawn imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static void disc(CGContextRef context, CGFloat x, CGFloat y, CGFloat radius) {
    CGContextFillEllipseInRect(context, CGRectMake(x - radius, y - radius, 2 * radius, 2 * radius));
}

static void ring(CGContextRef context, CGFloat x, CGFloat y, CGFloat radius) {
    CGContextStrokeEllipseInRect(context, CGRectMake(x - radius, y - radius, 2 * radius, 2 * radius));
}

// The two crossing arrows of a shuffle, over the whole grid.
static void crossingArrows(CGContextRef context) {
    CGContextMoveToPoint(context, 3, 7);
    CGContextAddLineToPoint(context, 6.2, 7);
    CGContextAddCurveToPoint(context, 8.2, 7, 9.4, 8, 10.5, 9.7);
    CGContextAddLineToPoint(context, 13.1, 13.9);
    CGContextAddCurveToPoint(context, 14.1, 15.6, 15.4, 16.5, 17.4, 16.5);
    CGContextAddLineToPoint(context, 20, 16.5);
    CGContextMoveToPoint(context, 17.5, 14.2);
    CGContextAddLineToPoint(context, 20.2, 16.5);
    CGContextAddLineToPoint(context, 17.5, 18.9);
    CGContextMoveToPoint(context, 3, 16.5);
    CGContextAddLineToPoint(context, 6.2, 16.5);
    CGContextAddCurveToPoint(context, 7.5, 16.5, 8.5, 16.1, 9.3, 15.3);
    CGContextMoveToPoint(context, 13.6, 8.4);
    CGContextAddCurveToPoint(context, 14.5, 7.5, 15.6, 7, 17.4, 7);
    CGContextAddLineToPoint(context, 20, 7);
    CGContextMoveToPoint(context, 17.5, 4.6);
    CGContextAddLineToPoint(context, 20.2, 7);
    CGContextAddLineToPoint(context, 17.5, 9.3);
    CGContextSetLineWidth(context, 1.8);
    CGContextStrokePath(context);
}

// A small drop earring hung at `x`: a ring, a stem, an orb, leaning by `lean`.
static void drop(CGContextRef context, CGFloat x, CGFloat lean) {
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, x, 14.9);
    CGContextRotateCTM(context, lean);
    CGContextScaleCTM(context, 0.95, 0.95);
    CGContextSetLineWidth(context, 1.0);
    ring(context, 0, 0, 1.05);
    CGContextMoveToPoint(context, 0, 1.05);
    CGContextAddLineToPoint(context, 0, 2.9);
    CGContextStrokePath(context);
    disc(context, 0, 5.3, 2.5);
    CGContextRestoreGState(context);
}

static UIImage *arrowsWithEarrings(CGFloat side) {
    return onGrid(side, ^(CGContextRef context) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, -1.6, -2.2);
        CGContextScaleCTM(context, 0.84, 0.84);
        crossingArrows(context);
        CGContextRestoreGState(context);
        // The corner the pair hangs in is cut out of the arrows first, so the two do not run together.
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(12.6, 12.4, 12, 12) cornerRadius:4] fillWithBlendMode:kCGBlendModeClear alpha:1];
        drop(context, 16.3, 0.14);
        drop(context, 20.7, -0.14);
    });
}

static UIImage *earringsOnArrows(CGFloat side) {
    return onGrid(side, ^(CGContextRef context) {
        CGContextMoveToPoint(context, 3, 5.5);
        CGContextAddLineToPoint(context, 6, 5.5);
        CGContextAddCurveToPoint(context, 8.6, 5.5, 9.6, 7.1, 10.6, 8.7);
        CGContextMoveToPoint(context, 13, 8.7);
        CGContextAddCurveToPoint(context, 14, 7.1, 15, 5.5, 17.6, 5.5);
        CGContextAddLineToPoint(context, 21, 5.5);
        CGContextMoveToPoint(context, 18.6, 3.2);
        CGContextAddLineToPoint(context, 21, 5.5);
        CGContextAddLineToPoint(context, 18.6, 7.8);
        CGContextSetLineWidth(context, 1.8);
        CGContextStrokePath(context);
        CGContextMoveToPoint(context, 8.2, 10.5);
        CGContextAddLineToPoint(context, 8.2, 13.5);
        CGContextMoveToPoint(context, 15.8, 10.5);
        CGContextAddLineToPoint(context, 15.8, 13.5);
        CGContextSetLineWidth(context, 1.6);
        CGContextStrokePath(context);
        disc(context, 8.2, 17.2, 3.6);
        disc(context, 15.8, 17.2, 3.6);
    });
}

static UIImage *twoIntoOne(CGFloat side) {
    return onGrid(side, ^(CGContextRef context) {
        CGContextSetLineWidth(context, 1.8);
        ring(context, 5, 6, 2.6);
        ring(context, 5, 18, 2.6);
        CGContextMoveToPoint(context, 7.8, 6.6);
        CGContextAddCurveToPoint(context, 11.2, 7.2, 12, 9.2, 13.2, 11);
        CGContextMoveToPoint(context, 7.8, 17.4);
        CGContextAddCurveToPoint(context, 11.2, 16.8, 12, 14.8, 13.2, 13);
        CGContextStrokePath(context);
        disc(context, 17.3, 12, 4.4);
    });
}

// Each drawing is made once a size.
static UIImage *made(NSString *name, CGFloat side, UIImage *(^make)(void)) {
    static NSCache<NSString *, UIImage *> *kept;
    if (!kept) kept = [NSCache new];
    NSString *key = [NSString stringWithFormat:@"%@ %.1f", name, side];
    UIImage *image = [kept objectForKey:key];
    if (image) return image;
    image = make();
    if (image) [kept setObject:image forKey:key];
    return image;
}

UIImage *SGFusionShuffleIcon(NSInteger drawing, CGFloat side) {
    if (drawing == 1) return made(@"hung", side, ^{ return earringsOnArrows(side); });
    return made(@"corner", side, ^{ return arrowsWithEarrings(side); });
}

UIImage *SGFusionIcon(SGFusionGlyph glyph, CGFloat side) {
    switch (glyph) {
        case SGFusionGlyphFusion: return SGFusionShuffleIcon(SGInt(SGKeyFusionIcon, 0), side);
        case SGFusionGlyphMerge: return made(@"merge", side, ^{ return twoIntoOne(side); });
        case SGFusionGlyphNoShuffle: return made(@"none", side, ^{ return badged(@"xmark", side); });
        case SGFusionGlyphSmart: return made(@"smart", side, ^{ return badged(@"sparkle", side); });
        default: return made(@"shuffle", side, ^{
            UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:side * 0.72 weight:UIImageSymbolWeightSemibold];
            return [[UIImage systemImageNamed:@"shuffle" withConfiguration:configuration] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        });
    }
}
