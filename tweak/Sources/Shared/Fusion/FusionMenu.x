// Playlist Fusion's two ways in on Spotify's own screens (Fusion.h), either look.
//
// A row "Playlist Fusion" under a playlist's menu, the sheet a long press on a playlist in the library opens
// (ContextMenu_InternalImpl.ContextMenuViewController, the same sheet every ⋯ opens). The sheet does not say
// what it is about in anything the tree shows but its heading, Components.UI.ContextMenuHeader, whose first
// label is the playlist's name: the row is added when that name is a playlist of the library's, and opens
// the merge with that playlist as the destination. It shares the footer with Download lossless, under it
// (SGLosslessFooter.h).
//
// A long press on a shuffle button, Components.UI.ShuffleButton on a playlist's or album's page (an
// EncoreButton of LegacyUI_ECMCoreKit), opens the shuffle choices with Fusion Shuffle among them. A tap is
// left as it is.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Headers/SPTPlayer.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lossless/SGLosslessFooter.h"
#import "Shared/Player/PlayerState.h"
#import "Fusion.h"

static const CGFloat kRowHeight = 56, kSideMargin = 16, kIconSide = 24;
static char kRowKey, kPressKey;
UIColor *(^SGFusionAccent)(void);

static UINavigationController *navigationIn(UIViewController *controller, int depth) {
    if (!controller || depth > 6) return nil;
    if ([controller isKindOfClass:UINavigationController.class]) return (UINavigationController *)controller;
    if ([controller isKindOfClass:UITabBarController.class]) {
        UINavigationController *selected = navigationIn(((UITabBarController *)controller).selectedViewController, depth + 1);
        if (selected) return selected;
    }
    for (UIViewController *child in controller.childViewControllers) {
        UINavigationController *found = navigationIn(child, depth + 1);
        if (found) return found;
    }
    return controller.navigationController;
}

static void show(UIViewController *page) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = SGTopController();
        UINavigationController *navigation = navigationIn(top, 0);
        SGShowPage(navigation.topViewController ?: top, page);
    });
}

#pragma mark - the row under a playlist's menu

@interface SGFusionMenuRow : UIControl
@property (nonatomic, weak) UIViewController *menu;
@property (nonatomic, copy) NSString *playlist;
@end

@implementation SGFusionMenuRow {
    UIImageView *_icon;
    UILabel *_title;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = [[UIImageView alloc] initWithImage:SGFusionIcon(SGFusionGlyphMerge, kIconSide)];
    _icon.tintColor = [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.80 : 0.65];
    _icon.contentMode = UIViewContentModeCenter;
    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:17];
    _title.textColor = UIColor.whiteColor;
    _title.text = @"Playlist Fusion";
    for (UIView *view in @[_icon, _title]) {
        view.userInteractionEnabled = NO;
        [self addSubview:view];
    }
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Playlist Fusion";
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(highlight) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(unhighlight) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _icon.frame = CGRectMake(kSideMargin, (kRowHeight - kIconSide) / 2, kIconSide, kIconSide);
    CGFloat titleX = kSideMargin + kIconSide + kSideMargin;
    _title.frame = CGRectMake(titleX, 0, MAX(0, self.bounds.size.width - titleX - kSideMargin), kRowHeight);
}

- (void)highlight {
    self.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)unhighlight {
    [UIView animateWithDuration:0.2 animations:^{ self.backgroundColor = UIColor.clearColor; }];
}

- (void)open {
    NSString *playlist = self.playlist;
    UIViewController *menu = self.menu;
    void (^go)(void) = ^{ show(SGFusionMergePage(playlist)); };
    if (menu.presentingViewController) [menu.presentingViewController dismissViewControllerAnimated:YES completion:go];
    else go();
}

@end

static UITableView *tableIn(UIView *root, int depth) {
    if ([root isKindOfClass:UITableView.class]) return (UITableView *)root;
    if (depth > 5) return nil;
    for (UIView *child in root.subviews) {
        UITableView *table = tableIn(child, depth + 1);
        if (table) return table;
    }
    return nil;
}

// The heading's first label: the name of what the menu is about.
static NSString *headingOf(UIView *root) {
    __block UIView *header = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!header && [view.accessibilityIdentifier isEqualToString:@"Components.UI.ContextMenuHeader"]) header = view;
    });
    __block NSString *name = nil;
    if (header) SGForEachView(header, ^(UIView *view) {
        if (!name && [view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) name = ((UILabel *)view).text;
    });
    return name;
}

// A playlist's menu is told by its rows where its heading is not a name the library is known to hold: every
// language Spotify ships says "playlist" in at least one of them (Delete playlist, Supprimer la playlist).
static BOOL aboutPlaylist(UITableView *table) {
    __block BOOL found = NO;
    SGForEachView(table, ^(UIView *view) {
        if (found || ![view isKindOfClass:UILabel.class]) return;
        NSString *text = ((UILabel *)view).text;
        if (text.length && [text rangeOfString:@"playlist" options:NSCaseInsensitiveSearch].location != NSNotFound) found = YES;
    });
    return found;
}

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    if (!root) return;
    UITableView *table = tableIn(root, 0);
    CGFloat width = table.bounds.size.width;
    if (!table || width <= 0) return;
    SGFusionMenuRow *row = objc_getAssociatedObject(menu, &kRowKey);
    if (!row) {
        // With the library's names not read, the row still opens the merge, with no destination picked yet.
        NSString *playlist = SGFusionPlaylistNamed(headingOf(root));
        if (!playlist) {
            SGFusionWarmNames(nil);
            if (!aboutPlaylist(table)) return;
        }
        row = [[SGFusionMenuRow alloc] initWithFrame:CGRectMake(0, 0, width, kRowHeight)];
        row.tag = 2;
        row.menu = menu;
        row.playlist = playlist;
        objc_setAssociatedObject(menu, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGLosslessFooterPlace(table, row, width, kRowHeight);
}

%hook _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)viewDidLayoutSubviews {
    %orig;
    install((UIViewController *)self);
}
%end

#pragma mark - the shuffle modes

// Spotify's button goes from none to shuffle to, where it offers it, smart shuffle, and back to none. Fusion
// Shuffle is put after its last: a tap that takes Spotify's shuffle from on to off starts it, and a tap while
// it is on ends it and leaves no shuffle. The tap itself is Spotify's; what follows is told from the player
// saying, within a moment of a tap on one of these buttons, that its shuffle turned.
@interface SGFusionBox : NSObject
@property (nonatomic, weak) UIView *view;
@end

@implementation SGFusionBox
@end

@interface SGFusionButtons : NSObject <SGPlayerStateObserver>
@end

static SGFusionButtons *sg_buttons;
static NSHashTable<UIView *> *sg_attached;
static CFAbsoluteTime sg_tapAt;
static BOOL sg_wasShuffling, sg_smart;
static char kGlyphKey, kDimmedKey, kRealKey;

static BOOL shufflingNow(void) {
    return SGPlaybackPlayer().state.options.shufflingContext;
}

// Spotify's shuffle set by the mod, not by a tap: what the player says next is not a tap's doing.
static void setSpotifyShuffle(BOOL on) {
    sg_tapAt = 0;
    id<SPTPlayer> player = SGPlaybackPlayer();
    if ([player respondsToSelector:@selector(setShufflingContext:)]) [player setShufflingContext:on];
}

static void note(NSString *text) {
    UIWindow *window = SGTopController().view.window;
    if (!window) return;
    UILabel *label = [UILabel new];
    label.text = [NSString stringWithFormat:@"  %@  ", text];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 2;
    label.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
    label.layer.cornerRadius = 14;
    label.clipsToBounds = YES;
    CGSize fit = [label sizeThatFits:CGSizeMake(window.bounds.size.width - 48, 80)];
    label.frame = CGRectMake((window.bounds.size.width - fit.width - 16) / 2, window.safeAreaInsets.top + 12, fit.width + 16, fit.height + 18);
    label.alpha = 0;
    [window addSubview:label];
    [UIView animateWithDuration:0.25 animations:^{ label.alpha = 1; } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:2.4 options:0 animations:^{ label.alpha = 0; } completion:^(BOOL done) { [label removeFromSuperview]; }];
    }];
}

NSInteger SGFusionModeNow(void) {
    if (SGFusionShuffleActive()) return SGFusionModeFusion;
    if (!shufflingNow()) return SGFusionModeNone;
    return sg_smart ? SGFusionModeSmart : SGFusionModeShuffle;
}

static UIControl *realControl(UIView *source) {
    SGFusionBox *box = objc_getAssociatedObject(source, &kRealKey);
    UIView *real = box.view ?: source;
    return [real isKindOfClass:UIControl.class] ? (UIControl *)real : nil;
}

static void after(NSTimeInterval seconds, void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// Smart Shuffle has no call of its own that is known: it is reached the way a finger reaches it, through
// Spotify's button, from none: one press for shuffle, a second for smart. Where the second press lands on
// none, Spotify does not offer it here, and plain shuffle is left on with a word saying so.
static void reachSmart(UIView *source) {
    UIControl *control = realControl(source);
    setSpotifyShuffle(NO);
    if (!control) {
        setSpotifyShuffle(YES);
        note(@"Smart Shuffle is not reachable from this button. Shuffle is on");
        return;
    }
    after(0.3, ^{
        sg_tapAt = 0;
        [control sendActionsForControlEvents:UIControlEventTouchUpInside];
        after(0.45, ^{
            sg_tapAt = 0;
            if (!shufflingNow()) {
                setSpotifyShuffle(YES);
                note(@"Smart Shuffle could not be reached. Shuffle is on");
                return;
            }
            [control sendActionsForControlEvents:UIControlEventTouchUpInside];
            after(0.45, ^{
                sg_tapAt = 0;
                if (shufflingNow()) {
                    sg_smart = YES;
                    return;
                }
                setSpotifyShuffle(YES);
                note(@"Spotify does not offer Smart Shuffle here. Shuffle is on");
            });
        });
    });
}

void SGFusionSetMode(NSInteger mode, UIView *source) {
    if (mode != SGFusionModeFusion && SGFusionShuffleActive()) SGFusionShuffleStop();
    sg_smart = NO;
    switch (mode) {
        case SGFusionModeNone:
            setSpotifyShuffle(NO);
            break;
        case SGFusionModeShuffle:
            // Off first: on from smart shuffle would leave it smart.
            setSpotifyShuffle(NO);
            after(0.25, ^{ setSpotifyShuffle(YES); });
            break;
        case SGFusionModeSmart:
            reachSmart(source);
            break;
        default:
            setSpotifyShuffle(NO);
            SGFusionShuffleStart();
    }
}

void SGFusionOpenSettings(void) {
    show(SGFusionSettingsPage());
}

// Fusion Shuffle's glyph over the button while it is on, the button's own drawing under it faded out, not
// hidden (Spotify's stacks crash on hidden), and brought back as it was when the mode ends.
static void dress(UIView *button) {
    UIImageView *glyph = objc_getAssociatedObject(button, &kGlyphKey);
    NSHashTable<UIView *> *dimmed = objc_getAssociatedObject(button, &kDimmedKey);
    if (!SGFusionShuffleActive()) {
        if (!glyph) return;
        glyph.alpha = 0;
        for (UIView *view in dimmed.allObjects) view.alpha = 1;
        [dimmed removeAllObjects];
        return;
    }
    if (!glyph) {
        glyph = [UIImageView new];
        glyph.userInteractionEnabled = NO;
        glyph.isAccessibilityElement = NO;
        glyph.contentMode = UIViewContentModeCenter;
        objc_setAssociatedObject(button, &kGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dimmed = [NSHashTable weakObjectsHashTable];
        objc_setAssociatedObject(button, &kDimmedKey, dimmed, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Each pass: the drawing is the one chosen in the settings, which can change while the button is up.
    glyph.image = SGFusionIcon(SGFusionGlyphFusion, 26);
    UIColor *lit = SGFusionAccent ? SGFusionAccent() : nil;
    glyph.tintColor = lit ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
    if (glyph.superview != button) [button addSubview:glyph];
    glyph.frame = button.bounds;
    glyph.alpha = 1;
    for (UIView *view in button.subviews) {
        if (view == glyph || view.alpha < 0.01) continue;
        view.alpha = 0;
        [dimmed addObject:view];
    }
}

@implementation SGFusionButtons

- (void)pressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    // The press is not a tap: what it lets go of turns nothing.
    sg_tapAt = 0;
    SGFusionShowModes(press.view);
}

- (void)tapped {
    sg_tapAt = CFAbsoluteTimeGetCurrent();
}

- (void)fusionChanged {
    for (UIView *button in sg_attached.allObjects) dress(button);
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    BOOL shuffling = state.options.shufflingContext;
    if (shuffling == sg_wasShuffling) return;
    sg_wasShuffling = shuffling;
    if (!shuffling) sg_smart = NO;
    BOOL tapped = CFAbsoluteTimeGetCurrent() - sg_tapAt < 1.5;
    sg_tapAt = 0;
    if (!tapped) return;
    if (SGFusionShuffleActive()) {
        // A tap during Fusion Shuffle: Spotify turned its own on, which is not what the tap is for here.
        if (shuffling) {
            SGFusionShuffleStop();
            setSpotifyShuffle(NO);
        }
    } else if (!shuffling) {
        SGFusionShuffleStart();
    }
}

@end

void SGFusionAttachShuffleMenu(UIView *button) {
    if (!button) return;
    if (!sg_buttons) {
        sg_buttons = [SGFusionButtons new];
        sg_attached = [NSHashTable weakObjectsHashTable];
        sg_wasShuffling = shufflingNow();
        SGAddPlayerStateObserver(sg_buttons);
        [NSNotificationCenter.defaultCenter addObserver:sg_buttons selector:@selector(fusionChanged) name:SGFusionShuffleDidChangeNotification object:nil];
    }
    if (!objc_getAssociatedObject(button, &kPressKey)) {
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:sg_buttons action:@selector(pressed:)];
        press.minimumPressDuration = 0.35;
        [button addGestureRecognizer:press];
        objc_setAssociatedObject(button, &kPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([button isKindOfClass:UIControl.class]) {
            [(UIControl *)button addTarget:sg_buttons action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
        } else {
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:sg_buttons action:@selector(tapped)];
            tap.cancelsTouchesInView = NO;
            [button addGestureRecognizer:tap];
        }
        [sg_attached addObject:button];
    }
    dress(button);
}

void SGFusionAttachShuffleStandIn(UIView *standIn, UIView *real) {
    if (!standIn) return;
    SGFusionBox *box = objc_getAssociatedObject(standIn, &kRealKey);
    if (!box) {
        box = [SGFusionBox new];
        objc_setAssociatedObject(standIn, &kRealKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    box.view = real;
    SGFusionAttachShuffleMenu(standIn);
}

%hook _TtC19LegacyUI_ECMCoreKitP33_7AC6ABDB5A3E514EA5239D6986C3C90912EncoreButton
- (void)didMoveToWindow {
    %orig;
    UIView *button = (UIView *)self;
    if (button.window && [button.accessibilityIdentifier isEqualToString:@"Components.UI.ShuffleButton"]) SGFusionAttachShuffleMenu(button);
}
- (void)layoutSubviews {
    %orig;
    UIView *button = (UIView *)self;
    if ([button.accessibilityIdentifier isEqualToString:@"Components.UI.ShuffleButton"]) SGFusionAttachShuffleMenu(button);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC24ContextMenu_InternalImpl25ContextMenuViewController",
                       @"_TtC19LegacyUI_ECMCoreKitP33_7AC6ABDB5A3E514EA5239D6986C3C90912EncoreButton"]);
}
