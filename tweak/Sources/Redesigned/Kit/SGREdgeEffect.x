#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "SGRAccentWash.h"

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

static BOOL alreadyLit(UIView *view) {
    for (int depth = 0; view && depth < 10; depth++, view = view.superview) {
        for (UIView *sub in view.subviews) {
            NSString *name = NSStringFromClass(sub.class);
            if ([name isEqualToString:@"SGBackdropHost"] || [name isEqualToString:@"SGRAccentWashView"]) return YES;
        }
    }
    return NO;
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
    NSString *name = NSStringFromClass(owner.class);
    return ![name containsString:@"NowPlaying"] && ![name containsString:@"Lyrics"] && ![name containsString:@"SideDrawer"];
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
    if (!alreadyLit(page)) SGRAccentWashPlace(page);
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
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
