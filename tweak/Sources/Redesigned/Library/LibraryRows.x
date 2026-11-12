#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Library.h"

static const CGFloat kTextGap = 12;

static char kThumbKey, kCoverKey, kLineKey, kCardKey, kGlassRowKey;
static const CGFloat kCardSide = 8, kCardGap = 5, kCardRadius = 22;

// A row of the list: a playlist, an artist, an album, or one of the rows that adds one (Add artists,
// Add podcasts, Import your music), all of them a ListRow 80 high across the page (the recorded library).
static BOOL listRow(UIView *cell) {
    CGSize size = cell.bounds.size;
    return size.width > 300 && size.height >= 56 && size.height <= 120;
}

// Spotify's dark fill on the row and what spans it, cleared so the glass shows.
static void clearRowFill(UIView *cell) {
    CGFloat across = cell.bounds.size.width * 0.9;
    NSMutableArray<UIView *> *spans = [NSMutableArray arrayWithObject:cell];
    for (NSUInteger i = 0; i < spans.count && i < 16; i++) {
        UIView *span = spans[i];
        if (span.bounds.size.width < across || [span isKindOfClass:UIVisualEffectView.class]) continue;
        CGFloat alpha = 0;
        UIColor *fill = span.backgroundColor;
        CGFloat r = 0, g = 0, b = 0;
        if (fill && [fill getRed:&r green:&g blue:&b alpha:&alpha] && alpha > 0.5 && MAX(r, MAX(g, b)) < 0.15) span.backgroundColor = UIColor.clearColor;
        [spans addObjectsFromArray:span.subviews];
    }
}

// Spotify gives a cover a square corner and an artist's picture a circle. Only the square becomes the Kit's.
static void roundCorners(UIView *artwork, CGFloat radius) {
    if (!artwork) return;
    CGFloat side = MIN(artwork.bounds.size.width, artwork.bounds.size.height);
    CALayer *layer = artwork.layer;
    if (side < 1 || layer.cornerRadius >= side / 2 - 0.5) return;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
    if (!layer.masksToBounds) layer.masksToBounds = YES;
}

static void hairline(UIView *cell, UIView *thumb) {
    CALayer *line = objc_getAssociatedObject(cell, &kLineKey);
    CGSize size = cell.bounds.size;
    CGRect artwork = thumb ? SGFrameIn(thumb, cell) : CGRectZero;
    BOOL wanted = thumb && size.width > 300 && size.height <= 120 && artwork.size.width > 1;
    if (!wanted) {
        if (line && !line.hidden) line.hidden = YES;
        return;
    }
    if (!line) {
        line = [CALayer layer];
        line.backgroundColor = SGRHairline().CGColor;
        objc_setAssociatedObject(cell, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superlayer != cell.layer) [cell.layer addSublayer:line];

    CGFloat thickness = 1.0 / MAX(1, cell.window.screen.scale ?: UIScreen.mainScreen.scale);
    CGFloat leading = CGRectGetMaxX(artwork) + kTextGap;
    CGRect frame = CGRectMake(leading, size.height - thickness, MAX(0, size.width - leading), thickness);
    if (line.hidden || !CGRectEqualToRect(line.frame, frame)) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        line.hidden = NO;
        line.frame = frame;
        [CATransaction commit];
    }
}

static void style(UIView *cell) {
    UIView *thumb = SGRFindByIdentifier(cell, @"Artwork.Row.Library", &kThumbKey);
    if (thumb) roundCorners(thumb, SGRRadiusThumb);
    else roundCorners(SGRFindByIdentifier(cell, @"Components.UI.CardLibrary.Artwork", &kCoverKey), SGRRadiusCover);
    BOOL glass = SGEnabled(SGRKeyLibraryGlass) && listRow(cell);
    objc_setAssociatedObject(cell, &kGlassRowKey, glass ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (glass) clearRowFill(cell);
    SGRGlassCard(cell, &kCardKey, CGRectInset(cell.bounds, kCardSide, kCardGap), kCardRadius, glass);
    if (glass) {
        CALayer *line = objc_getAssociatedObject(cell, &kLineKey);
        if (line && !line.hidden) line.hidden = YES;
    } else {
        hairline(cell, thumb);
    }

    // The first cell that held an artwork, so the line says what was found rather than what had not loaded yet.
    static BOOL logged;
    if (!logged && thumb && thumb.bounds.size.width > 1) {
        logged = YES;
        SGLog(@"redesign library: rows styled, first cell %@, thumbnail %@ at r=%.1f",
              NSStringFromCGSize(cell.bounds.size), NSStringFromCGSize(thumb.bounds.size), thumb.layer.cornerRadius);
    }
}


// Spotify sets a row's black fill again after its layout (as it appears, as a press ends): a dark fill set on
// a view of a library row with glass is cleared as it is set.
%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (color && SGEnabled(SGRKeyLibraryGlass) && [color getRed:&r green:&g blue:&b alpha:&a] && a > 0.5 && MAX(r, MAX(g, b)) < 0.15) {
        UIView *view = (UIView *)self;
        for (int depth = 0; view && depth < 6; depth++, view = view.superview) {
            if (objc_getAssociatedObject(view, &kGlassRowKey)) {
                %orig(UIColor.clearColor);
                return;
            }
        }
    }
    %orig;
}
%end

%hook _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
- (void)layoutSubviews {
    %orig;
    style((UIView *)self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer"]);
}
