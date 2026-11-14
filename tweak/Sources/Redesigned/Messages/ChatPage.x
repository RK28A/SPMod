// Messages redesign: a chat (Campfire_ChatPageImpl.ChatPageViewController, recorded tree 66e1f6b8) takes the
// theme behind it like Home, the other person's bubbles go clear with their outline and one's own take the
// accent, and the field to write in sits on the floating bars instead of where Spotify leaves room for its own
// tab bar, following them as they minimize and come back.
//
// Spotify lays the field out (its element view, a direct subview of the page at the foot) and the black
// panel under it; the field is only moved by a transform, never re-framed, and the list's bottom inset
// (its top, when it is drawn upside down) gives back the same distance.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Navbar/Navbar.h"

static const CGFloat kAboveBars = 6;   // the field's foot (its 16pt padding under the glass) over the bars' top
static char kInsetBaseKey, kInsetSetKey, kFillKey;
static __weak UIViewController *sg_chat;
static BOOL sg_keyboardUp;

static BOOL isBlack(UIColor *color) {
    CGFloat w = 1, a = 0;
    return color && [color getWhite:&w alpha:&a] && w < 0.05 && a > 0.5;
}

static BOOL isComposer(UIView *view) {
    return [NSStringFromClass(view.class) containsString:@"ChatMessageComposeElement"];
}

// Gives back to the list what the field moved down by, on the side its newest messages are on.
static void shiftList(UIScrollView *list, CGFloat delta) {
    BOOL upsideDown = list.transform.d < 0;
    UIEdgeInsets insets = list.contentInset;
    CGFloat now = upsideDown ? insets.top : insets.bottom;
    NSNumber *set = objc_getAssociatedObject(list, &kInsetSetKey), *base = objc_getAssociatedObject(list, &kInsetBaseKey);
    // Spotify setting its own inset since the last pass makes that the new base.
    CGFloat from = set && base && fabs(set.doubleValue - now) < 0.5 ? base.doubleValue : now;
    CGFloat want = MAX(0, from - delta);
    objc_setAssociatedObject(list, &kInsetBaseKey, @(from), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kInsetSetKey, @(want), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (fabs(want - now) < 0.5) return;
    if (upsideDown) insets.top = want;
    else insets.bottom = want;
    list.contentInset = insets;
    SGDebugOnce(@"redesign messages: the list gives back the field's move (upside down %d, inset %.0f -> %.0f)", upsideDown, from, want);
}

// Where the field goes: its foot just over the floating bars, or where Spotify put it while the keyboard is up.
static void placeComposer(UIViewController *chat, BOOL animated) {
    UIView *page = chat.viewIfLoaded;
    if (!page.window) return;
    UIView *composer = nil;
    UIScrollView *list = nil;
    for (UIView *sub in page.subviews) {
        if (!composer && isComposer(sub)) composer = sub;
        else if (!list && [sub isKindOfClass:UICollectionView.class]) list = (UIScrollView *)sub;
    }
    if (!composer) return;
    CGFloat delta = 0;
    CGFloat top = SGRFloatingBarsTop();
    if (!sg_keyboardUp && !isnan(top) && !composer.hidden) {
        CGFloat foot = [page convertPoint:CGPointMake(0, composer.center.y + composer.bounds.size.height / 2) toView:nil].y;
        delta = top + kAboveBars - foot;
        if (delta < -240 || delta > 320) delta = 0;
    }
    CGAffineTransform want = CGAffineTransformMakeTranslation(0, round(delta));
    if (!CGAffineTransformEqualToTransform(composer.transform, want)) {
        SGDebug(@"redesign messages: field moved by %.0f (bars top %.0f, keyboard %d)", delta, top, sg_keyboardUp);
        void (^move)(void) = ^{ composer.transform = want; };
        if (animated) [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0
                                          options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                                       animations:move completion:nil];
        else move();
    }
    if (list) shiftList(list, MAX(0, delta));
}

// The theme behind the chat; the black panel Spotify keeps under the field is cleared with the page's own fills.
static void themeChat(UIViewController *chat) {
    UIView *page = chat.viewIfLoaded;
    if (!page.window) return;
    SGRAccentWashPlace(page);
    CGFloat h = page.bounds.size.height;
    for (UIView *sub in page.subviews) {
        if (sub.class != UIView.class || sub.frame.origin.y < h * 0.4 || sub.bounds.size.width < page.bounds.size.width - 1) continue;
        if (!isBlack(sub.backgroundColor)) continue;
        sub.backgroundColor = UIColor.clearColor;
        objc_setAssociatedObject(sub, &kFillKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGDebugOnce(@"redesign messages: the panel under the field cleared");
    }
}

%hook _TtC21Campfire_ChatPageImpl22ChatPageViewController
- (void)viewWillAppear:(BOOL)animated {
    SGDebugOnce(@"hook Redesigned/Messages/ChatPage.x: -[ChatPageViewController viewWillAppear:] first call");
    %orig;
    sg_chat = self;
}

- (void)viewDidLayoutSubviews {
    SGDebugOnce(@"hook Redesigned/Messages/ChatPage.x: -[ChatPageViewController viewDidLayoutSubviews] first call");
    %orig;
    if (!SGLoopGuard("chat page")) return;
    sg_chat = self;
    themeChat(self);
    placeComposer(self, NO);
}
%end

// The message bubbles: Spotify's CornerRadiusView with the bubble's identifier. Black (the other person's,
// outlined) goes clear over the theme; grey (one's own) takes the accent.
static char kBubbleOriginalKey;

static UIColor *bubbleColor(UIView *view, UIColor *given) {
    if (![view.accessibilityIdentifier isEqualToString:@"MessageRowChat.bubble"] || !given) return given;
    CGFloat w = 1, a = 0;
    if (![given getWhite:&w alpha:&a] || a < 0.5) {
        CGFloat r, g, b;
        if (![given getRed:&r green:&g blue:&b alpha:&a]) return given;
        if (fabs(r - g) > 0.03 || fabs(g - b) > 0.03) return given;   // already coloured
        w = (r + g + b) / 3;
    }
    if (w < 0.05) return UIColor.clearColor;
    if (w < 0.3) return [SGRAccent() colorWithAlphaComponent:0.9];
    return given;
}

%hook _TtC15Campfire_ECMKitP33_C3D6A023C0D70E583A38568698C92DFC16CornerRadiusView
- (void)setBackgroundColor:(UIColor *)color {
    SGDebugOnce(@"hook Redesigned/Messages/ChatPage.x: -[CornerRadiusView setBackgroundColor:] first call");
    objc_setAssociatedObject(self, &kBubbleOriginalKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig(bubbleColor(self, color));
}

- (void)layoutSubviews {
    %orig;
    UIColor *original = objc_getAssociatedObject(self, &kBubbleOriginalKey);
    UIColor *want = bubbleColor(self, original);
    // The identifier can come after the colour: the first pass with both puts the right one in.
    if (original && want != original && ![self.backgroundColor isEqual:want]) [self setBackgroundColor:original];
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/Messages/ChatPage.x on");
    %init;
    SGRequireClasses(@[@"_TtC21Campfire_ChatPageImpl22ChatPageViewController",
                       @"_TtC15Campfire_ECMKitP33_C3D6A023C0D70E583A38568698C92DFC16CornerRadiusView"]);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:SGRTabBarDidMoveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        UIViewController *chat = sg_chat;
        if (chat) placeComposer(chat, YES);
    }];
    [center addObserverForName:UIKeyboardWillChangeFrameNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
        BOOL up = CGRectGetMinY(end) < UIScreen.mainScreen.bounds.size.height - 1 && end.size.height > 60;
        if (up == sg_keyboardUp) return;
        sg_keyboardUp = up;
        UIViewController *chat = sg_chat;
        if (chat) placeComposer(chat, YES);
    }];
}
