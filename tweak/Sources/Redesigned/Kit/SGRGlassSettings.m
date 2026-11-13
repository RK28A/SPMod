#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Core/SGGlass.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Redesigned/Library/Library.h"
#import "Redesigned/Playlist/Playlist.h"
#import "SGRAccent.h"
#import "SGRAccentWash.h"
#import "SGRGlassSettings.h"
#import "SGRThemedPane.h"

NSInteger SGRGlassStyleNow(void) {
    return [NSUserDefaults.standardUserDefaults integerForKey:SGRKeyGlassStyle];
}

double SGRGlassClearFill(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyGlassClear];
    return stored ? MIN(1, MAX(0, [stored doubleValue])) : 0.5;
}

NSInteger SGRGlassLookNow(void) {
    NSInteger style = SGRGlassStyleNow();
    return style * 1000 + (style == 1 ? (NSInteger)lround(SGRGlassClearFill() * 100) : 0);
}

UIVisualEffect *SGRGlassEffectNow(void) {
    Class glass = NSClassFromString(@"UIGlassEffect");
    if (![glass respondsToSelector:@selector(effectWithStyle:)]) return SGGlassEffect();
    NSInteger style = SGRGlassStyleNow();
    // UIGlassEffectStyle: 0 regular, 1 clear.
    UIVisualEffect *effect = [glass effectWithStyle:style == 1 ? 1 : 0];
    if (![effect respondsToSelector:@selector(setTintColor:)]) return effect;
    if (style == 2) {
        [effect setValue:[SGRAccentColor() ?: UIColor.whiteColor colorWithAlphaComponent:0.28] forKey:@"tintColor"];
    } else if (style == 1 && SGRGlassClearFill() > 0.5) {
        // Past half, white is let into the glass, up to a step from frosted.
        [effect setValue:[UIColor colorWithWhite:1 alpha:0.3 * (SGRGlassClearFill() - 0.5)] forKey:@"tintColor"];
    }
    return effect;
}

static double zoomAmount(void) {
    id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGRKeyGlassZoomAmount];
    return stored ? MIN(0.2, MAX(0.02, [stored doubleValue])) : 0.08;
}

void SGRGlassZoomList(UIScrollView *list) {
    // Asked on every frame of every scroll: a list is told from its class once, and with the zoom off and
    // never turned on in this list nothing more is done.
    static char kListKey, kZoomedKey;
    NSNumber *ours = objc_getAssociatedObject(list, &kListKey);
    if (!ours) {
        NSString *name = NSStringFromClass(list.class);
        ours = @([name containsString:@"YourLibraryCollectionView"] || [name containsString:@"FTPTouchCancellingCollectionView"]);
        objc_setAssociatedObject(list, &kListKey, ours, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!ours.boolValue) return;
    BOOL on = SGFlag(SGRKeyGlassZoom, NO);
    if (!on && !objc_getAssociatedObject(list, &kZoomedKey)) return;
    objc_setAssociatedObject(list, &kZoomedKey, on ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CGFloat middle = list.contentOffset.y + list.bounds.size.height / 2, half = MAX(1, list.bounds.size.height / 2);
    double amount = zoomAmount();
    for (UIView *row in list.subviews) {
        CGFloat height = row.bounds.size.height;
        if (height < 48 || height > 120 || row.bounds.size.width < list.bounds.size.width * 0.9) continue;
        CATransform3D scale = CATransform3DIdentity;
        if (on) {
            CGFloat away = MIN(1, fabs(row.center.y - middle) / half);
            CGFloat s = 1 - amount * away;
            scale = CATransform3DMakeScale(s, s, 1);
        }
        if (!CATransform3DEqualToTransform(row.layer.sublayerTransform, scale)) row.layer.sublayerTransform = scale;
    }
}

#pragma mark - the page

// What the choices look like, under the page's title: three rows of a library or of a playlist over the
// theme, as glass in the chosen style, the middle one zoomed when the zoom is on.
@interface SGRGlassPreview : UIView
@property (nonatomic) NSInteger showing;   // 0 library, 1 playlist
- (void)refresh;
@end

@implementation SGRGlassPreview {
    UISegmentedControl *_switcher;
    NSMutableArray<UIView *> *_rows;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = 22;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    _switcher = [[UISegmentedControl alloc] initWithItems:@[@"Library", @"Playlist"]];
    _switcher.selectedSegmentIndex = 0;
    [_switcher addTarget:self action:@selector(switched) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_switcher];
    _rows = [NSMutableArray array];
    return self;
}

- (void)switched {
    self.showing = _switcher.selectedSegmentIndex;
    [self refresh];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    SGRAccentWashPlace(self);
    _switcher.frame = CGRectMake(16, 12, self.bounds.size.width - 32, 30);
    [self bringSubviewToFront:_switcher];
    if (_rows.count == 0) [self refresh];
}

- (void)refresh {
    for (UIView *row in _rows) [row removeFromSuperview];
    [_rows removeAllObjects];
    BOOL library = self.showing == 0;
    BOOL glass = library ? SGEnabled(SGRKeyLibraryGlass) : SGFlag(SGRKeyPlaylistGlass, NO);
    NSArray<NSString *> *titles = library ? @[@"Liked Songs", @"Your playlist", @"An artist"] : @[@"First track", @"Second track", @"Third track"];
    CGFloat width = self.bounds.size.width, rowHeight = library ? 72 : 60, top = 54;
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, top + i * rowHeight, width, rowHeight)];
        if (glass) {
            static char key;
            SGRGlassCard(row, &key, CGRectInset(row.bounds, 8, library ? 5 : 3), library ? 22 : 18, YES);
        }
        CGFloat art = rowHeight - (library ? 20 : 16);
        UIView *cover = [[UIView alloc] initWithFrame:CGRectMake(20, (rowHeight - art) / 2, art, art)];
        cover.backgroundColor = [SGRAccentColor() ?: UIColor.grayColor colorWithAlphaComponent:0.6 + 0.15 * i];
        cover.layer.cornerRadius = library && i == 2 ? art / 2 : (library ? 12 : 6);
        [row addSubview:cover];
        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(32 + art, rowHeight / 2 - 18, width - art - 90, 20)];
        title.text = titles[i];
        title.textColor = UIColor.whiteColor;
        title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [row addSubview:title];
        UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(32 + art, rowHeight / 2 + 2, width - art - 90, 16)];
        subtitle.text = library ? (i == 2 ? @"Artist" : @"Playlist") : @"Artist";
        subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        subtitle.font = [UIFont systemFontOfSize:13];
        [row addSubview:subtitle];
        if (SGFlag(SGRKeyGlassZoom, NO) && i != 1) {
            CGFloat s = 1 - zoomAmount();
            row.layer.sublayerTransform = CATransform3DMakeScale(s, s, 1);
        }
        [self addSubview:row];
        [_rows addObject:row];
    }
}

@end

@interface SGRGlassPage : SGModPage
@property (nonatomic, strong) SGRGlassPreview *preview;
@end

@implementation SGRGlassPage

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width;
    UIView *holder = table.tableHeaderView;
    if (!holder || fabs(holder.bounds.size.width - width) > 0.5) {
        holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 290)];
        self.preview.frame = CGRectMake(16, 12, width - 32, 266);
        [holder addSubview:self.preview];
        table.tableHeaderView = holder;
    }
}

@end

UIViewController *SGRGlassSettingsPage(void) {
    SGRGlassPreview *preview = [SGRGlassPreview new];
    __weak SGRGlassPreview *weakPreview = preview;
    void (^refresh)(void) = ^{ [weakPreview refresh]; };
    SGModRow *library = SGWithSymbol(SGSwitchRow(@"Library", @"Each playlist, artist and button on a card of glass", SGRKeyLibraryGlass), @"square.stack");
    library.changed = ^(BOOL on) { refresh(); };
    SGModRow *playlist = SGWithSymbol(SGOptionRow(@"Playlist tracks", @"Each track and recommendation on a card of glass", SGRKeyPlaylistGlass), @"music.note.list");
    playlist.changed = ^(BOOL on) { refresh(); };
    SGModRow *style = SGWithSymbol(SGChoiceRow(@"Glass style", nil, SGRKeyGlassStyle, @[@"Frosted", @"Clear", @"Tinted", @"Outline"], 0), @"drop");
    style.choiceNotes = @[@"The system's glass, a little milky.", @"Fully see-through glass, the background sharp behind it.", @"Frosted glass tinted with the accent.",
                          @"No glass, only a bright rim: nothing is blurred, the lightest on the phone."];
    style.chosen = ^(NSInteger index) { refresh(); };
    SGModRow *clear = SGSliderRow(@"Clear glass fill", @"0% is the bare glass: its rim and the light it bends. 100% is a step from frosted.", 0, 1, 0.05,
        ^double { return SGRGlassClearFill(); },
        ^(double value) {
            [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGRKeyGlassClear];
            refresh();
        }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
    SGModRow *drawer = SGWithSymbol(SGOptionRow(@"Profile menu", @"Each row of the side menu on a card of glass", SGRKeyDrawerGlass), @"sidebar.left");
    SGModRow *zoom = SGWithSymbol(SGOptionRow(@"Zoom on lists", @"The row in the middle of the screen stands out from the others", SGRKeyGlassZoom), @"plus.magnifyingglass");
    zoom.changed = ^(BOOL on) { refresh(); };
    SGModRow *amount = SGSliderRow(@"Zoom strength", nil, 0.02, 0.2, 0.01, ^double { return zoomAmount(); },
        ^(double value) {
            [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGRKeyGlassZoomAmount];
            refresh();
        }, ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; });
    SGRGlassPage *page = [[SGRGlassPage alloc] initWithTitle:@"Liquid Glass" intro:nil sections:@[
        SGNotedSection(@"Surfaces", @[library, playlist, drawer], @"What is drawn on glass. Changes show at once."),
        SGNotedSection(@"Glass", @[style, clear], @"The fill only applies to the Clear style."),
        SGNotedSection(@"Zoom", @[zoom, amount], @"In the library and in playlists, the rows away from the middle of the screen are drawn a little smaller."),
    ] footer:nil];
    page.preview = preview;
    return page;
}
