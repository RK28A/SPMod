#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "SGRAccentWash.h"
#import "SGRThemedPane.h"
#import "Settings/SGBackdrop.h"

static void soften(UIScrollView *scrollView) {
    if (@available(iOS 26.0, *)) {
        // The style last set here, so a layout pass the setter itself causes does not set it again.
        static char setKey;
        UIScrollEdgeEffect *top = scrollView.topEdgeEffect;
        if (top.style == objc_getAssociatedObject(scrollView, &setKey)) return;
        UIScrollEdgeEffectStyle *soft = UIScrollEdgeEffectStyle.softStyle;
        top.style = soft;
        objc_setAssociatedObject(scrollView, &setKey, top.style, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"soft top edge: first scroll view %@", NSStringFromClass(scrollView.class)); });
    }
}

// Every page of Spotify's own made of one list over the whole screen, in the main window's navigation (the
// feed, Recents, the listening stats, the preferences, a playlist's...), gets the accent's light or the moving
// background behind it, as Home and the library have, and loses the top edge's frosted band, which drew a
// white haze over it. Told once each time the list comes on screen; placed again when its page changes size.
static char kThemedKey, kSizeKey;

// The page above `view` that already has the light or the background (Home, the library), and the view at
// its back that draws it.
static UIView *litAncestor(UIView *view, UIView **behind) {
    for (int depth = 0; view && depth < 10; depth++, view = view.superview) {
        for (UIView *sub in view.subviews) {
            NSString *name = NSStringFromClass(sub.class);
            if (![name isEqualToString:@"SGBackdropHost"] && ![name isEqualToString:@"SGRAccentWashView"]) continue;
            if (behind) *behind = sub;
            return view;
        }
    }
    return nil;
}

static BOOL wholePage(UIScrollView *list) {
    UIWindow *window = list.window;
    if (![list isKindOfClass:UICollectionView.class] || ![window.accessibilityIdentifier isEqualToString:@"spotify-main-window"]) return NO;
    CGSize size = list.bounds.size, screen = window.bounds.size;
    if (size.width < screen.width - 1 || size.height < screen.height * 0.8) return NO;
    UIViewController *owner = nil;
    for (UIResponder *r = list; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UINavigationController *navigation = owner.navigationController;
    if (!navigation || navigation.presentingViewController || [owner isKindOfClass:SGPage.class]) return NO;
    // The pages the redesign draws its own way (a playlist's, an album's, an artist's field of the cover's
    // colour, Search's tinted categories) keep it.
    NSString *name = NSStringFromClass(owner.class);
    for (NSString *own in @[@"NowPlaying", @"Lyrics", @"SideDrawer", @"Playlist", @"FTP", @"Album", @"Artist", @"Search", @"Podcast", @"Show"]) {
        if ([name containsString:own]) return NO;
    }
    return YES;
}

static void theme(UIScrollView *list) {
    NSNumber *told = objc_getAssociatedObject(list, &kThemedKey);
    if (!told) {
        told = @(wholePage(list));
        objc_setAssociatedObject(list, &kThemedKey, told, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (told.boolValue) {
            if (@available(iOS 26.0, *)) list.topEdgeEffect.hidden = YES;
        }
    }
    if (!told.boolValue) return;
    UIView *page = list.superview;
    NSString *size = NSStringFromCGSize(page.bounds.size);
    if ([objc_getAssociatedObject(list, &kSizeKey) isEqualToString:size]) return;
    objc_setAssociatedObject(list, &kSizeKey, size, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Home and the library place their own; a list inside them, which Spotify swaps for a new one as the
    // feed changes, has its fills between it and that light cleared, or the new one comes in black over it.
    UIView *behind = nil;
    UIView *lit = litAncestor(page, &behind);
    if (lit) SGBackdropClearFills(lit, behind);
    else SGRAccentWashPlace(page);
}

%hook UIScrollView
- (void)didMoveToWindow {
    %orig;
    objc_setAssociatedObject(self, &kThemedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &kSizeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (self.window) soften(self);
}

- (void)layoutSubviews {
    %orig;
    if (!self.window) return;
    soften(self);
    theme(self);
    // The frosted band at the top of any page-wide list of the main window goes, themed or not: it drew a
    // white haze over Home and a hard edge over a playlist's buttons.
    if (@available(iOS 26.0, *)) {
        CGSize size = self.bounds.size, screen = self.window.bounds.size;
        if (!self.topEdgeEffect.hidden && size.width >= screen.width - 1 && size.height >= screen.height * 0.6
            && [self.window.accessibilityIdentifier isEqualToString:@"spotify-main-window"]) self.topEdgeEffect.hidden = YES;
    }
    SGRThemedPaneFollow(self);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
