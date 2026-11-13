// The sheet of shuffle modes a long press on a shuffle button opens (Fusion.h): a card that comes up from the
// bottom edge over the whole width, in a window of its own, so it opens whatever Spotify has on screen and
// never waits on a controller that is busy. No Shuffle, Shuffle, Smart Shuffle and Fusion Shuffle from the
// top down; the one in use is drawn in the accent. Fusion Shuffle's row is two controls: the row turns the
// mode on, the arrow at its end opens the mode's settings and turns nothing on. A tap outside, a drag down
// or a choice closes it.
#import "Fusion.h"
#import "Core/SGCore.h"

static const CGFloat kRowHeight = 62, kRowGap = 10, kSide = 16, kArrowWidth = 58, kIcon = 28;

static UIColor *accent(void) {
    UIColor *color = SGFusionAccent ? SGFusionAccent() : nil;
    return color ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}

@interface SGFusionModeRow : UIView
@property (nonatomic, readonly) UIControl *main;
@property (nonatomic, readonly) UIButton *arrow;
- (instancetype)initWithGlyph:(SGFusionGlyph)glyph title:(NSString *)title detail:(NSString *)detail chosen:(BOOL)chosen arrow:(BOOL)arrow;
@end

@implementation SGFusionModeRow {
    UIImageView *_icon, *_check;
    UILabel *_title, *_detail;
    UIView *_divider;
}

- (instancetype)initWithGlyph:(SGFusionGlyph)glyph title:(NSString *)title detail:(NSString *)detail chosen:(BOOL)chosen arrow:(BOOL)arrow {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    UIColor *lit = accent();
    self.layer.cornerRadius = 18;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;
    self.backgroundColor = chosen ? [lit colorWithAlphaComponent:0.20] : [UIColor colorWithWhite:1 alpha:0.08];
    _main = [UIControl new];
    _main.isAccessibilityElement = YES;
    _main.accessibilityTraits = UIAccessibilityTraitButton | (chosen ? UIAccessibilityTraitSelected : 0);
    _main.accessibilityLabel = title;
    [_main addTarget:self action:@selector(down) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [_main addTarget:self action:@selector(up) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    [self addSubview:_main];
    _icon = [[UIImageView alloc] initWithImage:SGFusionIcon(glyph, kIcon)];
    _icon.tintColor = chosen ? lit : UIColor.whiteColor;
    _icon.contentMode = UIViewContentModeCenter;
    _title = [UILabel new];
    _title.text = title;
    _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _title.textColor = chosen ? lit : UIColor.whiteColor;
    _detail = [UILabel new];
    _detail.text = detail;
    _detail.font = [UIFont systemFontOfSize:13];
    _detail.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightBold]]];
    _check.tintColor = lit;
    _check.contentMode = UIViewContentModeCenter;
    _check.alpha = chosen ? 1 : 0;
    for (UIView *view in @[_icon, _title, _detail, _check]) {
        view.userInteractionEnabled = NO;
        [_main addSubview:view];
    }
    if (arrow) {
        _divider = [UIView new];
        _divider.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        [self addSubview:_divider];
        _arrow = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightMedium];
        [_arrow setImage:[UIImage systemImageNamed:@"chevron.right.circle.fill" withConfiguration:configuration] forState:UIControlStateNormal];
        _arrow.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
        _arrow.accessibilityLabel = [title stringByAppendingString:@" settings"];
        [self addSubview:_arrow];
    }
    return self;
}

- (void)down {
    _main.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
}

- (void)up {
    [UIView animateWithDuration:0.2 animations:^{ self->_main.backgroundColor = UIColor.clearColor; }];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    CGFloat mainWidth = _arrow ? width - kArrowWidth : width;
    _main.frame = CGRectMake(0, 0, mainWidth, height);
    _divider.frame = CGRectMake(mainWidth, 14, 1 / UIScreen.mainScreen.scale, height - 28);
    _arrow.frame = CGRectMake(mainWidth, 0, kArrowWidth, height);
    _icon.frame = CGRectMake(16, (height - kIcon) / 2, kIcon, kIcon);
    CGFloat textX = 16 + kIcon + 14, checkWidth = 30;
    _check.frame = CGRectMake(mainWidth - checkWidth - 10, 0, checkWidth, height);
    CGFloat textWidth = MAX(0, CGRectGetMinX(_check.frame) - textX - 6);
    if (_detail.text.length) {
        _title.frame = CGRectMake(textX, height / 2 - 20, textWidth, 22);
        _detail.frame = CGRectMake(textX, height / 2 + 2, textWidth, 17);
    } else {
        _title.frame = CGRectMake(textX, 0, textWidth, height);
        _detail.frame = CGRectZero;
    }
}

@end

@interface SGFusionSheetController : UIViewController
@property (nonatomic, weak) UIView *source;
@end

static UIWindow *sg_window;

@implementation SGFusionSheetController {
    UIView *_dim, *_card, *_grabber;
    UIVisualEffectView *_glass;
    UILabel *_title;
    NSArray<SGFusionModeRow *> *_rows;
    BOOL _closing;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _dim = [UIView new];
    _dim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _dim.alpha = 0;
    [_dim addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)]];
    [self.view addSubview:_dim];

    _card = [UIView new];
    _card.layer.cornerRadius = 32;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _card.clipsToBounds = YES;
    [_card addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)]];
    [self.view addSubview:_card];
    _glass = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    [_card addSubview:_glass];
    _grabber = [UIView new];
    _grabber.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
    _grabber.layer.cornerRadius = 2.5;
    [_card addSubview:_grabber];
    _title = [UILabel new];
    _title.text = @"Shuffle mode";
    _title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    _title.textColor = UIColor.whiteColor;
    _title.accessibilityTraits = UIAccessibilityTraitHeader;
    [_card addSubview:_title];

    NSInteger now = SGFusionModeNow();
    NSString *status = SGFusionShuffleActive() ? SGFusionShuffleStatus() : @"Every playlist you allow, mixed";
    NSArray<SGFusionModeRow *> *rows = @[
        [[SGFusionModeRow alloc] initWithGlyph:SGFusionGlyphNoShuffle title:@"No Shuffle" detail:nil chosen:now == SGFusionModeNone arrow:NO],
        [[SGFusionModeRow alloc] initWithGlyph:SGFusionGlyphShuffle title:@"Shuffle" detail:nil chosen:now == SGFusionModeShuffle arrow:NO],
        [[SGFusionModeRow alloc] initWithGlyph:SGFusionGlyphSmart title:@"Smart Shuffle" detail:nil chosen:now == SGFusionModeSmart arrow:NO],
        [[SGFusionModeRow alloc] initWithGlyph:SGFusionGlyphFusion title:@"Fusion Shuffle" detail:status chosen:now == SGFusionModeFusion arrow:YES],
    ];
    for (NSUInteger i = 0; i < rows.count; i++) {
        rows[i].main.tag = (NSInteger)i;
        [rows[i].main addTarget:self action:@selector(chose:) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:rows[i]];
    }
    [rows.lastObject.arrow addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    _rows = rows;
}

- (CGFloat)cardHeight {
    return 14 + 5 + 18 + 30 + 18 + _rows.count * kRowHeight + (_rows.count - 1) * kRowGap + 20 + self.view.safeAreaInsets.bottom;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    _dim.frame = bounds;
    CGFloat height = [self cardHeight];
    CGAffineTransform moved = _card.transform;
    _card.transform = CGAffineTransformIdentity;
    _card.frame = CGRectMake(0, bounds.size.height - height, bounds.size.width, height);
    _card.transform = moved;
    _glass.frame = _card.bounds;
    _grabber.frame = CGRectMake((bounds.size.width - 40) / 2, 10, 40, 5);
    _title.frame = CGRectMake(kSide + 6, 14 + 5 + 18, bounds.size.width - 2 * kSide - 12, 30);
    CGFloat y = CGRectGetMaxY(_title.frame) + 18;
    for (SGFusionModeRow *row in _rows) {
        row.frame = CGRectMake(kSide, y, bounds.size.width - 2 * kSide, kRowHeight);
        y += kRowHeight + kRowGap;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.view layoutIfNeeded];
    _card.transform = CGAffineTransformMakeTranslation(0, [self cardHeight]);
    [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.4 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_card.transform = CGAffineTransformIdentity;
        self->_dim.alpha = 1;
    } completion:nil];
}

- (void)closeThen:(void (^)(void))then {
    if (_closing) return;
    _closing = YES;
    [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self->_card.transform = CGAffineTransformMakeTranslation(0, [self cardHeight]);
        self->_dim.alpha = 0;
    } completion:^(BOOL finished) {
        sg_window.hidden = YES;
        sg_window.rootViewController = nil;
        sg_window = nil;
        if (then) then();
    }];
}

- (void)close {
    [self closeThen:nil];
}

- (void)dragged:(UIPanGestureRecognizer *)pan {
    CGFloat down = MAX(0, [pan translationInView:self.view].y);
    if (pan.state == UIGestureRecognizerStateChanged) {
        _card.transform = CGAffineTransformMakeTranslation(0, down);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (down > 90 || [pan velocityInView:self.view].y > 700) {
            [self close];
        } else {
            [UIView animateWithDuration:0.25 animations:^{ self->_card.transform = CGAffineTransformIdentity; }];
        }
    }
}

- (void)chose:(UIControl *)sender {
    NSInteger mode = sender.tag;
    UIView *source = self.source;
    [[UISelectionFeedbackGenerator new] selectionChanged];
    [self closeThen:^{ SGFusionSetMode(mode, source); }];
}

- (void)openSettings {
    [self closeThen:^{ SGFusionOpenSettings(); }];
}

@end

void SGFusionShowModes(UIView *source) {
    if (sg_window) return;
    UIWindowScene *scene = source.window.windowScene;
    if (!scene) {
        for (UIScene *each in UIApplication.sharedApplication.connectedScenes) {
            if ([each isKindOfClass:UIWindowScene.class] && each.activationState == UISceneActivationStateForegroundActive) scene = (UIWindowScene *)each;
        }
    }
    if (!scene) return;
    SGFusionSheetController *controller = [SGFusionSheetController new];
    controller.source = source;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    window.windowLevel = UIWindowLevelAlert - 1;
    window.backgroundColor = UIColor.clearColor;
    window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    window.rootViewController = controller;
    sg_window = window;
    window.hidden = NO;
}
