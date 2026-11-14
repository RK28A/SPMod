#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Artist.h"

static NSString *const kPageIdentifier = @"creator-page";

// Above for the bounce at the top of the page, below for the one at the end of it.
static const UIEdgeInsets kBleed = {600, 0, 600, 0};

static char kFieldKey;

#pragma mark - the page

UIView *SGRArtistPageOf(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageIdentifier]) return v;
    }
    return nil;
}

#pragma mark - the page's field

static SGRArtworkField *fieldOn(UIView *view) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, &kFieldKey);
        if (field) return field;
    }
    return nil;
}

UIColor *SGRArtistFieldColor(UIView *view) {
    SGRArtworkField *field = fieldOn(view);
    return field.fieldColor ?: SGRNeutralField();
}

void SGRArtistSetArtwork(UIView *view, UIImage *image) {
    if (image) [fieldOn(view) setArtwork:image identity:nil animated:YES];
}

static SGRArtworkField *fieldIn(UIView *page) {
    SGRArtworkField *field = objc_getAssociatedObject(page, &kFieldKey);
    if (field) return field;
    field = [[SGRArtworkField alloc] initWithFrame:page.bounds];
    field.bleed = kBleed;
    objc_setAssociatedObject(page, &kFieldKey, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakPage = page;
    [field whenColored:^{ SGRRevealMark(weakPage, SGRRevealColor); }];
    SGLog(@"redesign artist: field on the page %.0fx%.0f", page.bounds.size.width, page.bounds.size.height);
    return field;
}

%hook _TtC32CreativeWorkPlatform_TemplateKit12TemplateView
- (void)layoutSubviews {
    SGDebugOnce(@"hook Redesigned/Artist/ArtistField.x: -[TemplateView layoutSubviews] first call");
    %orig;
    UIView *page = (UIView *)self;
    if (![page.accessibilityIdentifier isEqualToString:kPageIdentifier] || page.bounds.size.height < 200) return;
    // The page the repaint hook keeps clear is the one laying out, which is the one on screen.
    sgr_artistRoot = page;
    SGRRevealHold(page, 0);
    SGRArtworkField *field = fieldIn(page);
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
}
%end

// The theme behind the sections under the header, risen out of the photo over the same distance as a
// playlist's (SGRThemedPane), in place of a hard edge where the photo stopped. The header is the cell at the top;
// the pane starts at the first cell below half the screen, the lowest such top seen.
static void themeUnderHeader(UIView *view) {
    static char kArtistTopKey;
    UIScrollView *list = [view isKindOfClass:UIScrollView.class] ? (UIScrollView *)view : nil;
    if (!list) {
        for (UIView *sub in view.subviews) if ([sub isKindOfClass:UICollectionView.class]) list = (UIScrollView *)sub;
    }
    if (!list || !list.window) return;
    CGFloat half = list.bounds.size.height * 0.35, top = CGFLOAT_MAX;
    for (UIView *cell in list.subviews) {
        if (![cell isKindOfClass:UICollectionViewCell.class] || cell.hidden) continue;
        CGFloat y = CGRectGetMinY(cell.frame);
        if (y > half && y < top) top = y;
    }
    NSNumber *seen = objc_getAssociatedObject(list, &kArtistTopKey);
    if (top == CGFLOAT_MAX && !seen) return;
    if (seen && seen.doubleValue <= top) {
        SGRThemedPaneFollow(list);
        return;
    }
    objc_setAssociatedObject(list, &kArtistTopKey, @(top), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SGDebug(@"redesign artist: theme under the header from %.0f", top);
    SGRThemedPane(list, top);
}

%hook _TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView
- (void)layoutSubviews {
    SGDebugOnce(@"hook Redesigned/Artist/ArtistField.x: -[CreativeWorkTemplateListView layoutSubviews] first call");
    %orig;
    UIView *list = (UIView *)self;
    if (!SGRArtistPageOf(list)) return;
    if (list.backgroundColor && SGIsBaseSurface(list.backgroundColor.CGColor)) list.backgroundColor = UIColor.clearColor;
    for (UIView *sub in list.subviews) {
        if (sub.backgroundColor && SGIsBaseSurface(sub.backgroundColor.CGColor)) sub.backgroundColor = UIColor.clearColor;
    }
    themeUnderHeader(list);
}
%end

#pragma mark - the tab strip

static void hideStrip(UIView *strip) {
    if (strip.alpha != 0) strip.alpha = 0;
    if (strip.userInteractionEnabled) strip.userInteractionEnabled = NO;
    strip.accessibilityElementsHidden = YES;
    CGFloat lift = CGRectGetHeight(strip.bounds);
    for (UIView *v in strip.superview.subviews) {
        if (![v isKindOfClass:UIScrollView.class]) continue;
        UIScrollView *pages = (UIScrollView *)v;
        if (pages.scrollEnabled) pages.scrollEnabled = NO;
        CGAffineTransform move = CGAffineTransformMakeTranslation(0, -lift);
        if (!CGAffineTransformEqualToTransform(pages.transform, move)) pages.transform = move;
    }
    static BOOL logged;
    if (!logged) {
        logged = YES;
        SGLog(@"redesign artist: the tab strip gone, the Music list up %.0fpt into its place", lift);
    }
}

// The strip's buttons are the one class of it Spotify names, and they lay out whenever the strip does.
%hook _TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton
- (void)layoutSubviews {
    SGDebugOnce(@"hook Redesigned/Artist/ArtistField.x: -[TabButton layoutSubviews] first call");
    %orig;
    if (!SGHidden(SGRKeyArtistHideTabs)) return;
    for (UIView *v = ((UIView *)self).superview; v; v = v.superview) {
        if (![v.accessibilityIdentifier isEqualToString:@"Components.UI.TabsSectionHeading"]) continue;
        if (SGRArtistPageOf(v)) hideStrip(v);
        return;
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/Artist/ArtistField.x on");
    %init;
    SGRequireClasses(@[
        @"_TtC32CreativeWorkPlatform_TemplateKit12TemplateView",
        @"_TtC32CreativeWorkPlatform_TemplateKit28CreativeWorkTemplateListView",
        @"_TtCOOOE16PodcastUI_ECMKitO19LegacyUI_ECMCoreKit10Components18TabsSectionHeading2UI7Private9TabButton",
    ]);
}
