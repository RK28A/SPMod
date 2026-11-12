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
    UIImage *glyph = [UIImage systemImageNamed:@"arrow.triangle.merge" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightRegular]];
    _icon = [[UIImageView alloc] initWithImage:glyph];
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

static void install(UIViewController *menu) {
    UIView *root = menu.viewIfLoaded;
    if (!root) return;
    UITableView *table = tableIn(root, 0);
    CGFloat width = table.bounds.size.width;
    if (!table || width <= 0) return;
    SGFusionMenuRow *row = objc_getAssociatedObject(menu, &kRowKey);
    if (!row) {
        NSString *playlist = SGFusionPlaylistNamed(headingOf(root));
        if (!playlist) {
            // The names not read yet this launch: read once, and the menu still open lays itself out again.
            __weak UIViewController *weakMenu = menu;
            SGFusionWarmNames(^{ [weakMenu.viewIfLoaded setNeedsLayout]; });
            return;
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

#pragma mark - the shuffle choices

@interface SGFusionShufflePress : NSObject
@end

@implementation SGFusionShufflePress

- (void)pressed:(UILongPressGestureRecognizer *)press {
    if (press.state != UIGestureRecognizerStateBegan) return;
    [[UIImpactFeedbackGenerator new] impactOccurred];
    id<SPTPlayer> player = SGPlaybackPlayer();
    BOOL shuffling = player.state.options.shufflingContext;
    BOOL fusion = SGFusionShuffleActive();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Shuffle" message:fusion ? SGFusionShuffleStatus() : nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:shuffling ? @"Spotify shuffle: turn off" : @"Spotify shuffle: turn on" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (fusion) SGFusionShuffleStop();
        if ([player respondsToSelector:@selector(setShufflingContext:)]) [player setShufflingContext:!shuffling];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:fusion ? @"Stop Fusion Shuffle" : @"Fusion Shuffle: mix every playlist" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (fusion) SGFusionShuffleStop();
        else SGFusionShuffleStart();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Fusion settings" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        show(SGFusionSettingsPage());
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = press.view;
    sheet.popoverPresentationController.sourceRect = press.view.bounds;
    [SGTopController() presentViewController:sheet animated:YES completion:nil];
}

@end

void SGFusionAttachShuffleMenu(UIView *button) {
    if (!button || objc_getAssociatedObject(button, &kPressKey)) return;
    static SGFusionShufflePress *target;
    if (!target) target = [SGFusionShufflePress new];
    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(pressed:)];
    press.minimumPressDuration = 0.45;
    [button addGestureRecognizer:press];
    objc_setAssociatedObject(button, &kPressKey, press, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
