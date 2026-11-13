#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Playlist.h"

// Under the text rather than the whole row, as the Music app draws it; the trailing end clears the page margin.
static const CGFloat kHairline = 0.5, kHairlineGap = 12;

static char kRowKey, kArtKey, kSubtitleKey, kLineKey, kToolbarKey, kCardKey, kTopKey;
static const CGFloat kCardSide = 8, kCardGap = 3, kCardRadius = 18;

// Glass rows (SGRKeyPlaylistGlass): a track's row on a card of glass, and from the first track down the
// theme seen through a sheet of glass (SGRThemedPane), the cover above left as it is. Where the tracks
// begin is the highest a track's row has been seen in the list.
static void glassTrack(UIView *cell, UIView *row) {
    // A track of the playlist or one of the suggestions under it: a list row of a track's height with art.
    CGFloat height = cell.bounds.size.height;
    // The theme stands behind the tracks in place of the cover's colour fading out, glass rows or not.
    BOOL track = row && height >= 48 && height <= 100;
    SGRGlassCard(cell, &kCardKey, CGRectInset(cell.bounds, kCardSide, kCardGap), kCardRadius, track && SGFlag(SGRKeyPlaylistGlass, NO));
    UIScrollView *list = [cell.superview isKindOfClass:UIScrollView.class] ? (UIScrollView *)cell.superview : nil;
    if (!track || !list) return;
    SGREntrance(cell, list);
    NSNumber *seen = objc_getAssociatedObject(list, &kTopKey);
    CGFloat top = CGRectGetMinY(cell.frame);
    if (seen && seen.doubleValue <= top) return;
    objc_setAssociatedObject(list, &kTopKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGRThemedPane(list, top);
}

static UIView *identified(UIView *root, NSString *identifier, const void *cacheKey) {
    return SGRFindByIdentifier(root, identifier, cacheKey);
}

static void clearSurface(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (color && SGIsBaseSurface(color.CGColor)) view.backgroundColor = UIColor.clearColor;
}

static void applyHairline(UIView *row, CGFloat leading) {
    CALayer *line = objc_getAssociatedObject(row, &kLineKey);
    if (!line) {
        line = [CALayer layer];
        line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        line.zPosition = 1;
        objc_setAssociatedObject(row, &kLineKey, line, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (line.superlayer != row.layer) [row.layer addSublayer:line];
    CGRect bounds = row.bounds;
    CGRect frame = CGRectMake(leading, bounds.size.height - kHairline,
                              MAX(0, bounds.size.width - leading - SGRSideMargin), kHairline);
    if (CGRectEqualToRect(line.frame, frame)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    line.frame = frame;
    [CATransaction commit];
}

static void glassTrack(UIView *cell, UIView *row);
static char kExtenderKey, kMoreKey;

// The ⋯ at the end of a track's row, drawn a little in from the edge.
static void insetMore(UIView *row) {
    UIView *more = SGRFindByIdentifier(row, @"Components.UI.ContextMenuButton", &kMoreKey);
    CGAffineTransform inset = CGAffineTransformMakeTranslation(-12, 0);
    if (more && !CGAffineTransformEqualToTransform(more.transform, inset)) more.transform = inset;
}

static void applyRow(UIView *cell) {
    clearSurface(cell);
    // Glyphs drawn in Spotify's green (download) take the accent on every pass, as the row is reused.
    SGRAccentRetint(cell);
    UIView *row = identified(cell, @"Encore.ListRow", &kRowKey);
    if (!row) {
        // A recommended track under the playlist is a row of another kind.
        UIView *extender = identified(cell, @"PlaylistExtender.Row", &kExtenderKey);
        if (extender) glassTrack(cell, extender);
        return;
    }
    insetMore(row);
    clearSurface(row);

    UIView *page = SGRPlaylistPageOf(cell);
    if (SGRRevealWaitsFor(page, SGRRevealList) && SGRRevealShowsText(row)) SGRRevealMark(page, SGRRevealList);

    CGFloat leading = SGRSideMargin + 48 + kHairlineGap;
    UIView *art = identified(row, @"Encore.ImageView", &kArtKey);
    if (art) {
        if (art.layer.cornerRadius != SGRRadiusThumb) {
            art.layer.cornerRadius = SGRRadiusThumb;
            art.layer.cornerCurve = kCACornerCurveContinuous;
            art.clipsToBounds = YES;
        }
        CGRect frame = [row convertRect:art.bounds fromView:art];
        if (frame.size.width > 0) leading = CGRectGetMaxX(frame) + kHairlineGap;
    }

    UIView *subtitle = identified(row, @"Track.Row.Content.Subtitle", &kSubtitleKey);
    SGForEachView(subtitle, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class]) return;
        for (UIView *p = v; p && p != subtitle; p = p.superview) {
            NSString *ident = p.accessibilityIdentifier;
            if ([ident isEqualToString:@"Components.UI.ExplicitIcon"] ||
                [ident isEqualToString:@"Podcast.Row.MarkAsPlayed.ExplicitIcon"] ||
                [ident isEqualToString:@"Components.UI.19andOverIcon"] ||
                [NSStringFromClass(p.class) hasSuffix:@"ExplicitBadge"]) return;
        }
        UILabel *label = (UILabel *)v;
        if (![label.textColor isEqual:SGRSecondary()]) label.textColor = SGRSecondary();
    });

    if (SGFlag(SGRKeyPlaylistGlass, NO)) {
        CALayer *line = objc_getAssociatedObject(row, &kLineKey);
        if (line && !line.hidden) line.hidden = YES;
    } else {
        applyHairline(row, leading);
    }
    glassTrack(cell, row);
}

// The header and the pills under it stay at the top of the page with nothing behind them, so the tracks
// passed under them in full view. A row is faded out as its top goes under their lower edge, and is gone
// before it is behind the pills. The header and the pills are the page's own views beside the list (the
// recorded tree): PL.Header, and the curation toolbar's content view.
static const CGFloat kUnder = 22;   // how far under the edge a row is before it is gone

static CGFloat barBottom(UIView *page, UIScrollView *list) {
    static Class pills;
    CGFloat bottom = 0;
    for (UIView *sub in page.subviews) {
        if (sub == list || sub.hidden || sub.alpha < 0.01) continue;
        if ([sub.accessibilityIdentifier isEqualToString:@"PL.Header"]) {
            bottom = MAX(bottom, CGRectGetMaxY(sub.frame));
        } else if (pills ? [sub isKindOfClass:pills] : [NSStringFromClass(sub.class) containsString:@"CurationActionsToolbar"]) {
            if (!pills) pills = sub.class;
            bottom = MAX(bottom, CGRectGetMaxY(sub.frame));
        }
    }
    return bottom;
}

// One mask on the list's layer, not a write on each row: a row's alpha set from inside the list's pass made
// the list lay out again for ever. The mask is a layer of the mod's own, so changing it lays nothing out.
static char kVeilKey;

static void fadeUnderBar(UIScrollView *list) {
    UIView *page = list.superview;
    if (!page || !list.window) return;
    CGFloat line = barBottom(page, list);
    CAGradientLayer *veil = objc_getAssociatedObject(list, &kVeilKey);
    // The header is the whole page tall while it opens: nothing is under a bar then.
    if (line <= 0 || line > page.bounds.size.height * 0.45) {
        if (veil && list.layer.mask == veil) {
            SGLoopNote("track veil off");
            list.layer.mask = nil;
        }
        return;
    }
    CGFloat height = list.bounds.size.height;
    if (height < 1) return;
    if (!veil) {
        veil = [CAGradientLayer layer];
        veil.colors = @[(id)UIColor.clearColor.CGColor, (id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor];
        objc_setAssociatedObject(list, &kVeilKey, veil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGFloat edge = line - CGRectGetMinY(list.frame);
    NSArray<NSNumber *> *stops = @[@0, @(MAX(0, edge - kUnder) / height), @(MAX(0, edge) / height), @1];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (list.layer.mask != veil) {
        SGLoopNote("track veil on");
        list.layer.mask = veil;
    }
    if (!CGRectEqualToRect(veil.frame, list.bounds)) veil.frame = list.bounds;
    if (![veil.locations isEqualToArray:stops]) veil.locations = stops;
    [CATransaction commit];
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    if (!SGLoopGuard("playlist list")) fadeUnderBar((UIScrollView *)self);
}
%end

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    %orig;
    UIView *cell = (UIView *)self;
    if (!SGRPlaylistHeaderOf(cell)) return;
    SGRClearCellPaint(cell);
    SGRPlaylistTakeCuration(cell);
    applyRow(cell);
}

- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *result = %orig;
    if (!SGRFindByIdentifier((UIView *)self, SGRPlaylistCurationIdentifier, &kToolbarKey)) return result;
    result.size = CGSizeMake(result.size.width, 0);
    ((UIView *)self).clipsToBounds = YES;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign playlist: curation pills asked for a height, answered 0"); });
    return result;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell"]);
}
