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

// A card of the grid (Grid view): a cover over its two lines, narrower than the page and taller than wide.
static BOOL gridCard(UIView *cell) {
    CGSize size = cell.bounds.size;
    return size.width >= 70 && size.width <= 220 && size.height > size.width && size.height <= size.width * 2;
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
    // A playlist's square with rounded corners; an artist's circle stays a circle.
    if (thumb) roundCorners(thumb, 12);
    else roundCorners(SGRFindByIdentifier(cell, @"Components.UI.CardLibrary.Artwork", &kCoverKey), SGRRadiusCover);
    // The grid's cards as the list's rows: clear of Spotify's black, and on glass when the library is.
    BOOL card = gridCard(cell), row = listRow(cell) || card;
    BOOL glass = SGEnabled(SGRKeyLibraryGlass) && row;
    objc_setAssociatedObject(cell, &kGlassRowKey, row ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (row) clearRowFill(cell);
    // Glyphs drawn in Spotify's green (pin, download) take the accent on every pass, as the row is reused.
    SGRAccentRetint(cell);
    SGRGlassCard(cell, &kCardKey, card ? CGRectInset(cell.bounds, -6, -6) : CGRectInset(cell.bounds, kCardSide, kCardGap), card ? 18 : kCardRadius, glass);
    if (card && cell.clipsToBounds) cell.clipsToBounds = NO;
    static BOOL loggedCard;
    if (card && !loggedCard) {
        loggedCard = YES;
        SGLog(@"redesign library: grid card %@ styled, glass %@", NSStringFromCGSize(cell.bounds.size), glass ? @"on" : @"off");
    }
    if (row && [cell.superview isKindOfClass:UIScrollView.class]) SGREntrance(cell, (UIScrollView *)cell.superview);
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
// a view of a library row is cleared as it is set. Every view of the app sets its fill through here, so the
// test is the cheapest that tells: nothing until the library has been opened, then the row's class up the
// view's parents before the colour is read at all.
static Class sg_rowClass;

%hook UIView
- (void)setBackgroundColor:(UIColor *)color {
    if (!sg_rowClass || !color) {
        %orig;
        return;
    }
    UIView *row = nil, *view = (UIView *)self;
    for (int depth = 0; view && depth < 6; depth++, view = view.superview) {
        if (object_getClass(view) != sg_rowClass) continue;
        row = view;
        break;
    }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (row && objc_getAssociatedObject(row, &kGlassRowKey) && [color getRed:&r green:&g blue:&b alpha:&a] && a > 0.5 && MAX(r, MAX(g, b)) < 0.15) {
        %orig(UIColor.clearColor);
        return;
    }
    %orig;
}
%end

%hook _TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer
- (void)layoutSubviews {
    %orig;
    if (!sg_rowClass) sg_rowClass = object_getClass(self);
    style((UIView *)self);
}
%end

// A row laid out before it had its size is styled again from the list's own pass, and a change of the glass
// switch reaches the rows on screen at once.
static NSHashTable<UIView *> *sg_lists;

%hook _TtC21YourLibrary_CommonKit25YourLibraryCollectionView
- (void)layoutSubviews {
    %orig;
    if (!sg_lists) sg_lists = [NSHashTable weakObjectsHashTable];
    [sg_lists addObject:(UIView *)self];
    for (UIView *row in ((UIView *)self).subviews) {
        if ([NSStringFromClass(row.class) containsString:@"SwipeableCollectionViewCellContainer"]) style(row);
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC21YourLibrary_CommonKit47YourLibrarySwipeableCollectionViewCellContainer"]);
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        for (UIView *list in sg_lists.allObjects) [list setNeedsLayout];
    }];
}
