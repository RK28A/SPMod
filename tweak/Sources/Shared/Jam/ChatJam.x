// Web Jam invites in Messages. The Jam button at the top right of a chat (Jam_ListeningActivityIntegrationImpl.
// MessagingHeaderLiquidGlassView, recorded tree 66e1f6b8) is taken over as the device picker's is
// (WebJamPicker.x): coloured in the accent while the Web Jam runs, a tap sends the Web Jam's address in the
// chat, a hold opens its settings. Spotify's own Jam needs Premium on its server.
//
// The invite is an ordinary message carrying a key (kKey + a nonce + the address), so a phone without the
// mod still reads a link. With the mod, a message holding the key is drawn nowhere (its row sized to nothing
// and see-through), on either side; one from the other person asks once whether to join, then opens the
// address. The Web Jam is served on the sender's Wi-Fi, so it only works on the same network.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Fusion/Fusion.h"
#import "WebJam.h"

static NSString *const kKey = @"⟦spjam:";
static NSString *const kSeenKey = @"spotifyglass.webjam.chatSeen";
static char kButtonKey, kFillKey, kHiddenKey;
static BOOL sg_inChat;

static UIColor *jamAccent(void) {
    return (SGFusionAccent ? SGFusionAccent() : nil) ?: SGAccentMark();
}

static UIView *findView(UIView *root, BOOL (^test)(UIView *view)) {
    if (!root) return nil;
    if (test(root)) return root;
    for (UIView *sub in root.subviews) {
        UIView *found = findView(sub, test);
        if (found) return found;
    }
    return nil;
}

static UIView *viewWithID(UIView *root, NSString *identifier) {
    return findView(root, ^BOOL(UIView *v) { return [v.accessibilityIdentifier isEqualToString:identifier]; });
}

#pragma mark - sending

static void alertOver(NSString *title, NSString *message) {
    UIViewController *top = SGTopController();
    if (!top) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [top presentViewController:alert animated:YES completion:nil];
}

// Writes the invite in the chat's own field and presses its send button, the draft put back after.
static void sendInvite(UIView *from, NSString *address) {
    UIView *root = from.window;
    UITextView *field = (UITextView *)viewWithID(root, @"Components.UI.MessageComposeView.textView");
    if (![field isKindOfClass:UITextView.class]) {
        SGLog(@"web jam chat: no message field found, nothing sent");
        alertOver(@"Couldn't send", @"The message field wasn't found on this chat.");
        return;
    }
    NSString *draft = field.text ?: @"";
    NSString *nonce = [[NSUUID UUID].UUIDString substringToIndex:8];
    NSString *text = [NSString stringWithFormat:@"🎧 Join my Jam: %@ (same Wi-Fi)\n%@%@|%@⟧", address, kKey, nonce, address];
    [field becomeFirstResponder];
    field.selectedRange = NSMakeRange(0, field.text.length);
    [field insertText:text];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *container = viewWithID(root, @"Components.UI.MessageComposeView.sendButton");
        UIControl *send = (UIControl *)findView(container, ^BOOL(UIView *v) { return [v isKindOfClass:UIControl.class] && v.userInteractionEnabled; });
        if (send) [send sendActionsForControlEvents:UIControlEventTouchUpInside];
        SGLog(@"web jam chat: invite %@ %@", nonce, send ? @"sent" : @"written, but no send button was found");
        if (!send) return;
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        if (!draft.length) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!field.text.length) [field insertText:draft];
        });
    });
}

// Started if it is off; the address comes once the server is listening on Wi-Fi.
static void inviteFrom(UIView *button, int tries) {
    NSString *address = SGWebJamJoinURL();
    if (address.length) {
        sendInvite(button, address);
        return;
    }
    if (tries == 0 && !SGWebJamRunning()) {
        SGWebJamSetEnabled(YES);
        SGLog(@"web jam chat: started for an invite");
    }
    if (tries >= 10) {
        SGLog(@"web jam chat: no address after 3 s (%@)", SGWebJamStatus());
        alertOver(@"Web Jam needs Wi-Fi", @"Connect to a Wi-Fi network: the person you invite must be on the same one.");
        return;
    }
    __weak UIView *weakButton = button;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *again = weakButton;
        if (again.window) inviteFrom(again, tries + 1);
    });
}

@interface SGChatJamButton : UIButton
@end

@implementation SGChatJamButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.clearColor;
        self.accessibilityLabel = @"Invite to Web Jam";
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(held:)]];
    }
    return self;
}

- (void)tapped {
    [[UIImpactFeedbackGenerator new] impactOccurred];
    SGLog(@"web jam chat: tap on the chat's Jam button");
    inviteFrom(self, 0);
    // The fill follows the Web Jam starting.
    __weak UIView *host = self.superview;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [host setNeedsLayout]; });
}

- (void)held:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    UIViewController *top = SGTopController();
    UIViewController *page = SGWebJamPage();
    if (!top || !page) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:page];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    page.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose primaryAction:
        [UIAction actionWithHandler:^(UIAction *action) { [navigation dismissViewControllerAnimated:YES completion:nil]; }] menu:nil];
    SGLog(@"web jam chat: long press, settings opened");
    [top presentViewController:navigation animated:YES completion:nil];
}
@end

// Our button over Spotify's, and the accent fill under its glyph while the Web Jam runs.
static void dressJamButton(UIView *view) {
    SGChatJamButton *button = objc_getAssociatedObject(view, &kButtonKey);
    if (!button) {
        button = [[SGChatJamButton alloc] initWithFrame:view.bounds];
        objc_setAssociatedObject(view, &kButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"web jam chat: the chat's Jam button taken over");
    }
    if (button.superview != view) [view addSubview:button];
    button.layer.zPosition = 10;
    if (!CGRectEqualToRect(button.frame, view.bounds)) button.frame = view.bounds;

    CALayer *fill = objc_getAssociatedObject(view, &kFillKey);
    if (!fill) {
        fill = [CALayer layer];
        objc_setAssociatedObject(view, &kFillKey, fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [view.layer insertSublayer:fill atIndex:0];
    }
    BOOL running = SGWebJamRunning();
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    fill.frame = CGRectInset(view.bounds, 1, 1);
    fill.cornerRadius = fill.frame.size.height / 2;
    fill.backgroundColor = [jamAccent() colorWithAlphaComponent:0.55].CGColor;
    fill.opacity = running ? 1 : 0;
    [CATransaction commit];
}

%hook _TtC36Jam_ListeningActivityIntegrationImpl30MessagingHeaderLiquidGlassView
- (void)layoutSubviews {
    SGDebugOnce(@"hook Shared/Jam/ChatJam.x: -[MessagingHeaderLiquidGlassView layoutSubviews] first call");
    %orig;
    dressJamButton(self);
}

- (void)didMoveToWindow {
    %orig;
    if (self.window) dressJamButton(self);
}
%end

#pragma mark - receiving

static NSString *keyedText(UIView *cell, UIView **textView) {
    __block NSString *found = nil;
    UIView *view = findView(cell, ^BOOL(UIView *v) {
        if (![v isKindOfClass:UITextView.class]) return NO;
        NSString *text = ((UITextView *)v).attributedText.string ?: ((UITextView *)v).text;
        if (![text containsString:kKey]) return NO;
        found = text;
        return YES;
    });
    if (textView) *textView = view;
    return found;
}

// The nonce and the address out of the key; nil when it doesn't read.
static NSArray<NSString *> *readKey(NSString *text) {
    NSRange start = [text rangeOfString:kKey];
    if (start.location == NSNotFound) return nil;
    NSString *rest = [text substringFromIndex:NSMaxRange(start)];
    NSRange end = [rest rangeOfString:@"⟧"];
    if (end.location != NSNotFound) rest = [rest substringToIndex:end.location];
    NSArray<NSString *> *parts = [rest componentsSeparatedByString:@"|"];
    if (parts.count != 2 || ![parts[1] hasPrefix:@"http"]) return nil;
    return parts;
}

static BOOL isMine(UIView *textView, UIView *cell) {
    NSString *label = textView.accessibilityLabel.lowercaseString ?: @"";
    if ([label hasPrefix:@"votre message"] || [label hasPrefix:@"your message"]) return YES;
    if ([label containsString:@"envoyé par"] || [label containsString:@"sent by"]) return NO;
    return [textView convertRect:textView.bounds toView:cell].origin.x > 60;
}

static NSString *senderName(UIView *textView) {
    NSString *label = textView.accessibilityLabel ?: @"";
    for (NSString *word in @[@" par ", @" by "]) {
        NSRange by = [label rangeOfString:word];
        if (by.location == NSNotFound) continue;
        NSString *rest = [label substringFromIndex:NSMaxRange(by)];
        NSRange colon = [rest rangeOfString:@":"];
        if (colon.location != NSNotFound) rest = [rest substringToIndex:colon.location];
        rest = [rest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (rest.length) return rest;
    }
    return nil;
}

static void offerToJoin(NSString *nonce, NSString *address, NSString *who) {
    NSMutableArray *seen = [[NSUserDefaults.standardUserDefaults arrayForKey:kSeenKey] ?: @[] mutableCopy];
    if ([seen containsObject:nonce]) return;
    [seen addObject:nonce];
    while (seen.count > 60) [seen removeObjectAtIndex:0];
    [NSUserDefaults.standardUserDefaults setObject:seen forKey:kSeenKey];
    NSURL *url = [NSURL URLWithString:address];
    UIViewController *top = SGTopController();
    if (!url || !top) return;
    SGLog(@"web jam chat: invite %@ received, asking to join", nonce);
    NSString *title = who.length ? [NSString stringWithFormat:@"Join %@'s Jam?", who] : @"Join the Jam?";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
        message:@"You need to be on the same Wi-Fi as them. It opens in your browser." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Join" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGLog(@"web jam chat: joining %@", address);
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }]];
    alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [top presentViewController:alert animated:YES completion:nil];
}

// A row holding an invite: drawn nowhere and sized to nothing. Rows are reused, so every sizing says again.
%hook _TtC12Element_List18CollectionViewCell
- (UICollectionViewLayoutAttributes *)preferredLayoutAttributesFittingAttributes:(UICollectionViewLayoutAttributes *)attributes {
    UICollectionViewLayoutAttributes *fitted = %orig;
    if (!sg_inChat) return fitted;
    UIView *textView = nil;
    NSString *text = keyedText(self, &textView);
    BOOL keyed = text != nil;
    BOOL was = [objc_getAssociatedObject(self, &kHiddenKey) boolValue];
    if (keyed != was) {
        objc_setAssociatedObject(self, &kHiddenKey, @(keyed), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        self.contentView.layer.opacity = keyed ? 0 : 1;
        self.isAccessibilityElement = NO;
        self.contentView.accessibilityElementsHidden = keyed;
    }
    if (!keyed) return fitted;
    CGRect frame = fitted.frame;
    frame.size.height = 1;
    fitted.frame = frame;
    NSArray<NSString *> *key = readKey(text);
    if (key && !isMine(textView, self)) {
        NSString *who = senderName(textView);
        dispatch_async(dispatch_get_main_queue(), ^{ offerToJoin(key[0], key[1], who); });
    }
    return fitted;
}
%end

%hook _TtC21Campfire_ChatPageImpl22ChatPageViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    sg_inChat = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    sg_inChat = NO;
}
%end

%ctor {
    SGDebug(@"module Shared/Jam/ChatJam.x on");
    %init;
    SGRequireClasses(@[@"_TtC36Jam_ListeningActivityIntegrationImpl30MessagingHeaderLiquidGlassView",
                       @"_TtC12Element_List18CollectionViewCell"]);
}
