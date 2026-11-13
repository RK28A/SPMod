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
static char kDimmedKey;
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

static void fadeUnderBar(UIScrollView *list) {
    UIView *page = list.superview;
    if (!page || !list.window) return;
    CGFloat line = barBottom(page, list);
    // The header is the whole page tall while it opens: nothing is under a bar then.
    if (line <= 0 || line > page.bounds.size.height * 0.45) line = -1000;
    CGFloat shift = CGRectGetMinY(list.frame) - list.contentOffset.y;
    for (UIView *cell in list.subviews) {
        if (![cell isKindOfClass:UICollectionViewCell.class]) continue;
        CGFloat shown = MIN(1, MAX(0, (CGRectGetMinY(cell.frame) + shift - line + kUnder) / kUnder));
        BOOL dimmed = objc_getAssociatedObject(cell, &kDimmedKey) != nil;
        if (shown >= 1 && !dimmed) continue;
        if (fabs(cell.alpha - shown) > 0.01) cell.alpha = shown;
        if ((shown < 1) != dimmed) objc_setAssociatedObject(cell, &kDimmedKey, shown < 1 ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl32FTPTouchCancellingCollectionView
- (void)layoutSubviews {
    %orig;
    // The fade under the pinned bar set each track's alpha from inside the list's own pass, and the list laid
    // out again on it 400 times a frame (the log's loop guard): off until it is done another way.
    (void)fadeUnderBar;
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
