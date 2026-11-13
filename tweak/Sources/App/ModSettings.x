#import <objc/runtime.h>
#import <objc/message.h>
#import "Shared/Fusion/Fusion.h"
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Settings/SGGlowSwitch.h"
#import "Native/Home/Home.h"
#import "Shared/AdBlock/AdBlock.h"
#import "Shared/Player/PlayerSettings.h"
#import "Redesigned/Album/Album.h"
#import "Redesigned/Artist/Artist.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Library/Library.h"
#import "Redesigned/Lyrics/Sing.h"
#import "Redesigned/Playlist/Playlist.h"
#import "Redesigned/Search/Search.h"
#import "Shared/Sing/SGSingModel.h"
#import "Shared/Flags/Flags.h"
#import "Shared/AudioEffects/AudioEffectsPage.h"
#import "Shared/Ambient/Ambient.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/Jam/WebJam.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Shared/HeadGestures/HeadGestures.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Downloads/Downloads.h"
#import "Shared/Matrix/MatrixDisplay.h"
#import "Shared/Lossless/SLDownloadsPage.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "App/About/About.h"
#import "App/DevTools/Developer.h"
#import "Pages.h"
#import "Redesigned/Kit/SGRAccentWash.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRThemedPane.h"
#import "Redesigned/Kit/SGRGlassSettings.h"

static const CGFloat kRowHeight = 56;
static char kRowKey, kInsetKey;

// The Misc page's switch that hides the Discord banner row in modSettingsPage below.
#define SGKeyHideDiscordBanner @"spotifyglass.hide.discordBanner"
// Off until switched on: the rows of the menu the profile picture opens that lead nowhere useful in a modded
// app are taken out of it (trimDrawer below).
#define SGKeyDrawerUseless @"spotifyglass.drawer.useless"

static SGModRow *pageRow(NSString *title, NSString *symbol, UIViewController *(^page)(void)) {
    return SGWithSymbol(SGPageRow(title, page), symbol);
}

@interface SGRootSettingsPage : SGModPage <UITextFieldDelegate>
- (instancetype)initWithSections:(NSArray<SGModSection *> *)sections;
@end

@implementation SGRootSettingsPage {
    NSArray<SGModSection *> *_allSections;
    NSArray<SGModSection *> *_indexedChildSections;
    UIView *_masthead;
    UILabel *_mastheadTitle, *_mastheadByline, *_compactTitle;
    UISearchTextField *_searchField;
    BOOL _compactTitleVisible;
}

- (instancetype)initWithSections:(NSArray<SGModSection *> *)sections {
    if (!(self = [super initWithTitle:@"SPMod" intro:nil sections:sections footer:@"Contributor: @Pulse-Ice (EeveeImmersive)\nBug fixes: @darkit"])) return nil;
    _allSections = [sections copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _masthead = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 168)];
    _masthead.backgroundColor = UIColor.clearColor;
    _masthead.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _mastheadTitle = [UILabel new];
    _mastheadTitle.text = @"SPMod";
    _mastheadTitle.font = [UIFont systemFontOfSize:36 weight:UIFontWeightBold];
    _mastheadTitle.textAlignment = NSTextAlignmentRight;
    [_mastheadTitle sizeToFit];
    _mastheadTitle.textColor = UIColor.whiteColor;
    _mastheadByline = [UILabel new];
    _mastheadByline.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _mastheadByline.textColor = [UIColor colorWithWhite:1 alpha:0.72];
    _mastheadByline.textAlignment = NSTextAlignmentRight;
    _searchField = [[UISearchTextField alloc] initWithFrame:CGRectZero];
    _searchField.placeholder = @"Search settings";
    _searchField.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _searchField.returnKeyType = UIReturnKeyDone;
    _searchField.clearButtonMode = UITextFieldViewModeWhileEditing;
    _searchField.delegate = self;
    [_searchField addTarget:self action:@selector(searchChanged:) forControlEvents:UIControlEventEditingChanged];
    [_masthead addSubview:_mastheadTitle];
    [_masthead addSubview:_mastheadByline];
    [_masthead addSubview:_searchField];
    self.tableView.tableHeaderView = _masthead;

    _compactTitle = [UILabel new];
    _compactTitle.text = @"SPMod";
    _compactTitle.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [_compactTitle sizeToFit];
    _compactTitle.textColor = UIColor.whiteColor;
    _compactTitle.alpha = 0;
    _compactTitle.isAccessibilityElement = YES;
    _compactTitle.accessibilityElementsHidden = YES;
    self.navigationItem.titleView = _compactTitle;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

static void collectSectionsFromPage(NSString *prefix, SGModPage *page, NSMutableArray<SGModSection *> *into, int depth) {
    if (![page isKindOfClass:SGModPage.class] || depth > 2) return;
    for (SGModSection *sec in page.sections) {
        NSString *secTitle = sec.title.length ? [NSString stringWithFormat:@"%@ › %@", prefix, sec.title] : prefix;
        [into addObject:SGSection(secTitle, sec.rows)];
        for (SGModRow *row in sec.rows) {
            if (row.page && depth < 2) {
                UIViewController *child = row.page();
                if ([child isKindOfClass:SGModPage.class]) {
                    collectSectionsFromPage([NSString stringWithFormat:@"%@ › %@", prefix, row.title], (SGModPage *)child, into, depth + 1);
                }
            }
        }
    }
}

- (NSArray<SGModSection *> *)indexedChildSections {
    if (_indexedChildSections) return _indexedChildSections;
    NSMutableArray<SGModSection *> *collected = [NSMutableArray array];
    for (SGModSection *sec in _allSections) {
        for (SGModRow *row in sec.rows) {
            if (!row.page || [row.title isEqualToString:@"All flags"]) continue;
            UIViewController *child = row.page();
            if ([child isKindOfClass:SGModPage.class]) {
                collectSectionsFromPage(row.title, (SGModPage *)child, collected, 1);
            }
        }
    }
    _indexedChildSections = [collected copy];
    return _indexedChildSections;
}

- (void)searchChanged:(UITextField *)field {
    NSString *query = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) {
        [self setSections:_allSections];
        return;
    }
    NSMutableArray<SGModSection *> *results = [NSMutableArray array];
    NSMutableArray<SGModRow *> *rootMatches = [NSMutableArray array];
    for (SGModSection *sec in _allSections) {
        for (SGModRow *row in sec.rows) {
            if ([row.title localizedCaseInsensitiveContainsString:query]
                || (row.subtitle && [row.subtitle localizedCaseInsensitiveContainsString:query])) {
                [rootMatches addObject:row];
            }
        }
    }
    if (rootMatches.count) [results addObject:SGSection(@"Pages", rootMatches)];
    for (SGModSection *sec in [self indexedChildSections]) {
        NSMutableArray<SGModRow *> *matchingRows = [NSMutableArray array];
        for (SGModRow *row in sec.rows) {
            if ([row.title localizedCaseInsensitiveContainsString:query]
                || (row.subtitle && [row.subtitle localizedCaseInsensitiveContainsString:query])
                || (sec.title && [sec.title localizedCaseInsensitiveContainsString:query])) {
                [matchingRows addObject:row];
            }
        }
        if (matchingRows.count) [results addObject:SGSection(sec.title, matchingRows)];
    }
    [self setSections:results];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _mastheadByline.text = @"by RK28A";
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width > 0) {
        BOOL sizeChanged = _masthead.bounds.size.width != width || _masthead.bounds.size.height != 168;
        _masthead.frame = CGRectMake(0, 0, width, 168);
        if (sizeChanged || self.tableView.tableHeaderView != _masthead) self.tableView.tableHeaderView = _masthead;
        _masthead.backgroundColor = UIColor.clearColor;
        _mastheadByline.textColor = UIColor.whiteColor;
        CGSize title = _mastheadTitle.bounds.size;
        _mastheadTitle.frame = CGRectMake(MAX(16, width - 16 - title.width), 24 + (48 - title.height) / 2, title.width, title.height);
        _mastheadByline.frame = CGRectMake(16, 72, MAX(0, width - 32), 24);
        _searchField.frame = CGRectMake(16, 110, MAX(0, width - 32), 38);
    }
    [self updateCompactTitleForScrollView:self.tableView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updateCompactTitleForScrollView:scrollView];
}

- (void)updateCompactTitleForScrollView:(UIScrollView *)scrollView {
    CGFloat scrolled = scrollView.contentOffset.y + scrollView.adjustedContentInset.top;
    BOOL show = scrolled >= CGRectGetHeight(_masthead.bounds);
    if (show == _compactTitleVisible) return;
    _compactTitleVisible = show;
    if (show) {
        _compactTitle.accessibilityElementsHidden = NO;
        [UIView animateWithDuration:0.18 animations:^{ self->_compactTitle.alpha = 1; }];
    } else {
        _compactTitle.accessibilityElementsHidden = YES;
        [UIView animateWithDuration:0.18 animations:^{ self->_compactTitle.alpha = 0; }];
    }
}

@end

static UIViewController *miscSettingsPage(void) {
    SGModRow *hideSigning = SGHideRow(@"Hide the lock screen alert", @"Hide the notice that this build cannot be opened from the lock screen", SGKeyHideSigningWarning);
    SGModRow *hideDiscord = SGSwitchRow(@"Hide the Discord banner", @"Hide the row here that advertises the Discord server", SGKeyHideDiscordBanner);
    SGModRow *useless = SGOptionRow(@"Display useless things in menu", @"In the menu your profile picture opens", SGKeyDrawerUseless);
    useless.info = @"Off, these are removed from the menu your profile picture opens:\n\n• Your subscription (Votre abonnement)\n• Messages\n• New message (Nouveau message)\n\nOn, Spotify's menu is shown whole. The change shows the next time the menu opens.";
    SGModSection *banners = SGSection(nil, @[
        SGWithSymbol(hideSigning, @"lock.slash"),
        SGWithSymbol(hideDiscord, @"bubble.left.and.bubble.right"),
        SGWithSymbol(useless, @"line.3.horizontal.decrease"),
    ]);
    SGModSection *devices = SGSection(@"Displays", @[SGWithSymbol(pageRow(@"iDotMatrix", @"dot.radiowaves.left.and.right", ^UIViewController *{ return SGMatrixSettingsPage(); }), @"dot.radiowaves.left.and.right")]);
    return [[SGModPage alloc] initWithTitle:@"Misc" intro:SGRestartNote sections:@[banners, devices] footer:nil];
}

static UIViewController *modSettingsPage(void) {
    // Opening the page is the only thing that asks; the cache keeps it to once every six hours.
    SGCheckForUpdate();
    NSMutableArray<SGModSection *> *sections = [NSMutableArray array];
    SGModRow *signing = SGSigningWarningRow();
    if (signing) signing.visible = ^BOOL { return !SGFlag(SGKeyHideSigningWarning, NO); };
    NSMutableArray<SGModRow *> *topRows = [NSMutableArray array];
    SGModRow *update = SGActionRow(@"SPMod update available", @"Tap to view the latest release", ^{
        NSString *url = SGUpdateNewestRelease().url;
        if (url.length) SGOpenURL(url);
    });
    update.symbol = @"arrow.down.circle.fill";
    update.color = SGGreen();
    update.visible = ^BOOL { return SGUpdateVersion() != nil; };
    update.refreshOn = SGUpdateCheckedNotification;
    [topRows addObject:update];
    SGModRow *discord = SGLinkRow(@"Join the Discord", @"Release pings, help and previews", SGDiscordURL);
    discord.image = SGDiscordIcon();
    discord.color = SGDiscordColor();
    discord.visible = ^BOOL { return !SGFlag(SGKeyHideDiscordBanner, YES); };
    [topRows addObject:discord];
    if (signing) [topRows addObject:signing];
    [sections addObject:SGSection(nil, topRows)];
    SGModRow *mod = pageRow(@"Mod", @"info.circle", ^UIViewController *{ return SGAboutPage(); });
    mod.value = ^NSString *{ return @(SG_VERSION); };
    // The audio effects work on the sound, so both looks have them, with what they are doing beside the chevron.
    SGModRow *audioEffects = pageRow(@"Audio effects", @"slider.vertical.3", ^UIViewController *{ return SGDSPSettingsPage(); });
    audioEffects.value = ^NSString *{ return SGDSPSummary(); };
    SGModRow *downloads = pageRow(@"Downloads", @"arrow.down.circle", ^UIViewController *{ return SGDownloadsSettingsPage(); });
    downloads.value = ^NSString *{ return SGDownloadsRowSummary(); };
    downloads.refreshOn = SGDownloadsDidChangeNotification;
    SGModRow *ambient = pageRow(@"Ambient", @"cloud.rain", ^UIViewController *{ return SGAmbientSettingsPage(); });
    ambient.value = ^NSString *{ return SGAmbientSummary(); };
    ambient.refreshOn = SGAmbientDidChangeNotification;
    // Web Jam also lives under Premium, ads & privacy → Jam; the root row makes the browser queue findable.
    SGModRow *webJam = pageRow(@"Web Jam", @"globe", ^UIViewController *{ return SGWebJamPage(); });
    webJam.value = ^NSString *{ return SGWebJamStatus(); };
    webJam.refreshOn = SGWebJamDidChangeNotification;
    NSMutableArray<SGModRow *> *parts = [NSMutableArray arrayWithArray:@[
        pageRow(@"Appearance", @"paintpalette", ^UIViewController *{ return SGAppearanceSettingsPage(); }),
        pageRow(@"Navbar", @"dock.rectangle", ^UIViewController *{ return SGNavbarPage(); }),
        pageRow(@"Player", @"play.circle", ^UIViewController *{ return SGPlayerSettingsPage(); }),
        pageRow(@"Lyrics", @"quote.bubble", ^UIViewController *{ return SGLyricsSettingsPage(); }),
        SGWithImage(SGPageRow(@"Fusion Shuffle", ^UIViewController *{ return SGFusionSettingsPage(); }), SGFusionIcon(SGFusionGlyphFusion, 18)),
        downloads,
        pageRow(@"Lossless & Soulseek", @"sparkles", ^UIViewController *{ return [SLDownloadsPage new]; }),
        pageRow(@"Your files", @"folder", ^UIViewController *{ return SGLocalFilesSettingsPage(); }),
        pageRow(@"Lock Screen", @"lock.iphone", ^UIViewController *{ return SGLockScreenSettingsPage(); }),
        audioEffects,
        ambient,
        pageRow(@"AutoMix", @"waveform.path", ^UIViewController *{ return SGAutoMixSettingsPage(); }),
        webJam,
        pageRow(@"Vibrations", @"iphone.radiowaves.left.and.right", ^UIViewController *{ return SGVibrationsSettingsPage(); }),
    ]];
    if (@available(iOS 17.0, *)) {
        SGModRow *liveActivity = pageRow(@"Live Activity", @"platter.filled.top.iphone", ^UIViewController *{ return SGLiveActivitySettingsPage(); });
        liveActivity.value = ^NSString *{ return SGLiveActivitySummary(); };
        [parts addObject:liveActivity];
    }
    [parts addObjectsFromArray:@[
        pageRow(@"AirPods gestures", @"airpods.pro", ^UIViewController *{ return SGHeadGesturesSettingsPage(); }),
        pageRow(@"Listening stats", @"chart.bar", ^UIViewController *{ return SGListeningStatsPage(); }),
    ]];
    if (SGRedesignedUIStored()) {
        [parts addObject:pageRow(@"Home", @"house", ^UIViewController *{ return SGRHomeSettingsPage(); })];
        [parts addObject:pageRow(@"Search", @"magnifyingglass", ^UIViewController *{ return SGRSearchSettingsPage(); })];
        [parts addObject:pageRow(@"Library", @"books.vertical", ^UIViewController *{ return SGRLibrarySettingsPage(); })];
        [parts addObject:pageRow(@"Playlists", @"music.note.list", ^UIViewController *{ return SGRPlaylistSettingsPage(); })];
        [parts addObject:pageRow(@"Albums", @"square.stack", ^UIViewController *{ return SGRAlbumSettingsPage(); })];
        [parts addObject:pageRow(@"Artists", @"person.2", ^UIViewController *{ return SGRArtistSettingsPage(); })];
    }
    else [parts addObject:pageRow(@"Home & Library", @"house", ^UIViewController *{ return SGHomeSettingsPage(); })];
    [parts addObject:pageRow(@"Misc", @"ellipsis.circle", ^UIViewController *{ return miscSettingsPage(); })];
    [parts addObject:pageRow(@"Developer", @"hammer", ^UIViewController *{ return SGDeveloperPage(); })];
    // Sing's microphone is the redesigned player's, so Karaoke is the redesign's; its row follows a download.
    if (SGRedesignedUIStored()) {
        SGModRow *karaoke = pageRow(@"Karaoke", @"music.mic", ^UIViewController *{ return SGRKaraokeSettingsPage(); });
        karaoke.value = ^NSString *{ return SGRKaraokeSummary(); };
        karaoke.refreshOn = SGSingModelDidChangeNotification;
        [sections addObject:SGSection(nil, @[karaoke])];
    }
    [sections addObjectsFromArray:@[
        SGSection(nil, parts),
        SGSection(nil, @[
            pageRow(@"Premium, ads & privacy", @"crown", ^UIViewController *{ return SGAdsSettingsPage(); }),
            pageRow(@"Labs", @"testtube.2", ^UIViewController *{ return SGLabsPage(); }),
        ]),
        SGSection(nil, @[
            pageRow(@"All flags", @"flag", ^UIViewController *{ return SGAllFlagsPage(); }),
            mod,
        ]),
    ]];
    return [[SGRootSettingsPage alloc] initWithSections:sections];
}

#pragma mark - row in the settings list

static UIColor *planBadgeColor(void);

@interface SGModSettingsRow : UIControl
@property (nonatomic) BOOL drawer;
@end

@implementation SGModSettingsRow {
    UIImageView *_icon;
    UILabel *_title;
    UIImageView *_chevron;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _icon = SGSymbolView(@"slider.horizontal.3", 20, UIImageSymbolWeightRegular, 24);
    _title = [UILabel new];
    _title.text = @"SPMod settings";
    _title.textColor = UIColor.whiteColor;
    _chevron = SGSymbolView(@"chevron.right", 11, UIImageSymbolWeightSemibold, 12);
    for (UIView *v in @[_icon, _title, _chevron]) [self addSubview:v];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _title.font = SGTitleFont();
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height, lead = self.drawer ? 4 : 0;
    _icon.frame = CGRectMake(12 + lead, (height - 24) / 2, 24, 24);
    _title.frame = CGRectMake(48 + lead, 0, width - 96, height);
    _chevron.frame = CGRectMake(width - 24, (height - 12) / 2, 12, 12);
    _chevron.hidden = NO;
    if (self.drawer) [self standOut];
}

// In the drawer the row is a pill of the accent's colour, its icon and chevron in the accent, its title bold,
// so it is the first thing seen there.
- (void)standOut {
    UIColor *accent = planBadgeColor();
    self.layer.cornerRadius = MIN(16, self.bounds.size.height / 2 - 4);
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.backgroundColor = [accent colorWithAlphaComponent:0.32];
    self.layer.borderWidth = 1.5;
    self.layer.borderColor = [accent colorWithAlphaComponent:0.9].CGColor;
    self.layer.shadowColor = accent.CGColor;
    self.layer.shadowOpacity = 0.55;
    self.layer.shadowRadius = 10;
    self.layer.shadowOffset = CGSizeZero;
    _icon.tintColor = UIColor.whiteColor;
    _chevron.tintColor = UIColor.whiteColor;
    _title.textColor = UIColor.whiteColor;
    _title.font = [UIFont systemFontOfSize:_title.font.pointSize + 1 weight:UIFontWeightHeavy];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

static UINavigationController *navigationIn(UIViewController *page) {
    if ([page isKindOfClass:UINavigationController.class]) return (UINavigationController *)page;
    for (UIViewController *child in page.childViewControllers) {
        UINavigationController *found = navigationIn(child);
        if (found) return found;
    }
    return nil;
}

- (void)open {
    UIViewController *owner = nil;
    for (UIResponder *r = self; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UIViewController *presenting = self.drawer ? owner.presentingViewController : nil;
    if (presenting) {
        [presenting dismissViewControllerAnimated:YES completion:^{
            SGShowPage(navigationIn(presenting).topViewController ?: presenting, modSettingsPage());
        }];
        return;
    }
    SGShowPage(owner, modSettingsPage());
}

@end

// The tab bar's controller holds no stack itself; the selected tab's sits among its parent's children.
void SGOpenModSettings(UIView *source) {
    UIViewController *owner = nil;
    for (UIResponder *r = source; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UINavigationController *nav = nil;
    for (UIViewController *page = owner; page && !nav; page = page.parentViewController) nav = navigationIn(page);
    SGShowPage(nav.topViewController ?: SGTopController(), modSettingsPage());
}

static void placeRow(UICollectionView *list, SGModSettingsRow *row) {
    SGAdoptFonts(list, row);
    CGFloat bottom = list.contentSize.height;
    row.hidden = !row.drawer && bottom <= 0;
    row.frame = row.drawer ? CGRectMake(12, -kRowHeight + 4, list.bounds.size.width - 24, kRowHeight - 8)
                           : CGRectMake(0, bottom, list.bounds.size.width, kRowHeight);

    UIEdgeInsets inset = list.contentInset;
    NSValue *applied = objc_getAssociatedObject(list, &kInsetKey);
    if (applied && UIEdgeInsetsEqualToEdgeInsets(inset, applied.UIEdgeInsetsValue)) return;
    if (row.drawer) inset.top += kRowHeight;
    else inset.bottom += kRowHeight;
    objc_setAssociatedObject(list, &kInsetKey, [NSValue valueWithUIEdgeInsets:inset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    list.contentInset = inset;
}

static SGModSettingsRow *ensureDrawerRow(UICollectionView *list) {
    SGModSettingsRow *row = objc_getAssociatedObject(list, &kRowKey);
    if (!row) {
        row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        row.drawer = YES;
        objc_setAssociatedObject(list, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (row.superview != list) [list addSubview:row];
    return row;
}

static UIViewController *settingsListIn(UIViewController *page, Class kind) {
    if ([page isKindOfClass:kind]) return page;
    for (UIViewController *child in page.childViewControllers) {
        UIViewController *found = settingsListIn(child, kind);
        if (found) return found;
    }
    return nil;
}

static BOOL isSettingsRoot(UIViewController *list) {
    for (UIViewController *page in list.navigationController.viewControllers) {
        UIViewController *found = settingsListIn(page, list.class);
        if (found) return found == list;
    }
    return YES;
}

%hook _TtC21Settings_PlatformImpl26SettingsListViewController
- (void)viewDidLayoutSubviews {
    %orig;
    BOOL root = isSettingsRoot((UIViewController *)self);
    for (UIView *sub in ((UIViewController *)self).view.subviews) {
        if (![sub isKindOfClass:UICollectionView.class]) continue;
        SGModSettingsRow *row = objc_getAssociatedObject(sub, &kRowKey);
        if (!root) {
            [row removeFromSuperview];
            objc_setAssociatedObject(sub, &kRowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            continue;
        }
        if (row) continue;
        row = [[SGModSettingsRow alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(sub, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sub addSubview:row];
    }
}
%end

static UIColor *planBadgeColor(void) {
    if (!SGRedesignedUI()) return SGGreen();
    if (SGRAccentColor()) return SGRAccentColor();
    NSInteger rgb = SGInt(@"spotifyglass.redesign.accent", 0x37F200);
    if (rgb < 0 || rgb > 0xFFFFFF) return SGGreen();
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static __weak UIView *sg_drawerRoot;
static char kPlanBadgeLabelKey;

static NSString *sidebarBadgeText(void) {
    NSString *text = [NSUserDefaults.standardUserDefaults stringForKey:SGKeySidebarBadgeText];
    return text.length ? text : @"SPMod";
}

static BOOL isSidebarBadgeText(NSString *text) {
    return [text isEqualToString:@"Spotify Free"] || [text isEqualToString:@"Taurine"]
        || [text isEqualToString:@"SPMod"] || [text isEqualToString:sidebarBadgeText()];
}

static BOOL isDrawerBadgeLabel(UILabel *label) {
    for (UIView *view = label; view; view = view.superview) {
        if (view == sg_drawerRoot ||
            [NSStringFromClass(view.class) containsString:@"SideDrawerListCollectionView"]) return YES;
    }
    return NO;
}

static BOOL isPlanBadgeLabel(UILabel *label) {
    return objc_getAssociatedObject(label, &kPlanBadgeLabelKey) != nil || isSidebarBadgeText(label.text);
}

static void stylePlanBadgeLabel(UILabel *label) {
    UIColor *color = planBadgeColor();
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    NSString *text = sidebarBadgeText();
    if (![label.text isEqualToString:text]) label.text = text;
    label.textColor = (0.2126 * red + 0.7152 * green + 0.0722 * blue) > 0.55 ? UIColor.blackColor : UIColor.whiteColor;
    label.backgroundColor = color;
    label.layer.backgroundColor = color.CGColor;
    label.layer.cornerRadius = MIN(8, CGRectGetHeight(label.bounds) / 2);
    label.clipsToBounds = YES;
    objc_setAssociatedObject(label, &kPlanBadgeLabelKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CGRect labelBounds = label.bounds;
    for (UIView *badge = label.superview; badge && badge != sg_drawerRoot; badge = badge.superview) {
        CGRect labelFrame = [label convertRect:labelBounds toView:badge];
        if (badge.bounds.size.width > CGRectGetWidth(labelFrame) + 80 ||
            badge.bounds.size.height > CGRectGetHeight(labelFrame) + 32) break;
        badge.backgroundColor = color;
        badge.layer.backgroundColor = color.CGColor;
        badge.layer.cornerRadius = MIN(8, CGRectGetHeight(badge.bounds) / 2);
        badge.layer.masksToBounds = YES;
    }
}

static void updatePlanBadge(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UILabel.class]) return;
        UILabel *label = (UILabel *)view;
        if (!isPlanBadgeLabel(label)) return;
        stylePlanBadgeLabel(label);
    });
}

static void fadeUselessLabel(UILabel *label);

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    fadeUselessLabel(self);
    if (![text isEqualToString:@"Spotify Free"] && ![text isEqualToString:@"Taurine"] &&
        ![text isEqualToString:@"SPMod"]) return;
    if (!isDrawerBadgeLabel(self)) return;
    stylePlanBadgeLabel(self);
}
%end

// The drawer without what is no use in it (SGKeyDrawerUseless): the row to the subscription, and Messages with
// its New message row. No tree of the drawer is recorded, so a row is told by how its text starts, in English
// and French. A row taken out is faded, not hidden, and stops taking touches; every row under it is moved up
// by its height, so no gap is left. The list's own layout puts them back on each pass and this runs after it.
static char kTrimmedKey;

static BOOL uselessText(NSString *text) {
    if (!text.length) return NO;
    for (NSString *start in @[@"Votre abonnement", @"Your subscription", @"Your plan", @"Your Premium", @"Messages",
                              @"Partagez vos coups", @"Share what you", @"Nouveau message", @"New message"]) {
        if ([text hasPrefix:start]) return YES;
    }
    return NO;
}

static BOOL uselessRow(UIView *row) {
    __block BOOL found = NO;
    SGForEachView(row, ^(UIView *view) {
        if (!found && [view isKindOfClass:UILabel.class] && uselessText(((UILabel *)view).text)) found = YES;
    });
    return found;
}

static BOOL rowHasText(UIView *row) {
    __block BOOL found = NO;
    SGForEachView(row, ^(UIView *view) {
        if (!found && [view isKindOfClass:UILabel.class] && ((UILabel *)view).text.length) found = YES;
    });
    return found;
}

// The useless rows, by where the list has them: a row is known by its words, and the subscription row is
// drawn as a grey skeleton before its words come, so its place is what tells it then.
static NSMutableSet<NSIndexPath *> *sg_gone;

#pragma mark - the drawer's rows closed up

// A faded row left its place empty. The list's own layout is taught to give every row under a useless one
// that much less, so the rows close up: the layout object of this one list gets a subclass made for it,
// whose answers are its parent's with the heights of the rows gone above taken off. No view is moved by
// hand, which is what stacked the rows on each other before.
static NSArray<NSValue *> *goneFrames(UICollectionViewLayout *layout, Class base) {
    UICollectionView *list = layout.collectionView;
    NSMutableArray<NSValue *> *frames = [NSMutableArray array];
    for (NSIndexPath *path in sg_gone) {
        if (path.section >= list.numberOfSections || path.item >= [list numberOfItemsInSection:path.section]) continue;
        struct objc_super up = {layout, base};
        UICollectionViewLayoutAttributes *given = ((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&up, @selector(layoutAttributesForItemAtIndexPath:), path);
        if (given && given.frame.size.height > 0.5) [frames addObject:[NSValue valueWithCGRect:given.frame]];
    }
    return frames;
}

static CGFloat goneHeight(NSArray<NSValue *> *gone) {
    CGFloat total = 0;
    for (NSValue *each in gone) total += each.CGRectValue.size.height;
    return total;
}

static UICollectionViewLayoutAttributes *lifted(UICollectionViewLayoutAttributes *given, NSArray<NSValue *> *gone) {
    if (!given || !gone.count) return given;
    BOOL out = given.representedElementCategory == UICollectionElementCategoryCell && [sg_gone containsObject:given.indexPath];
    CGFloat top = CGRectGetMinY(given.frame), lift = 0;
    for (NSValue *each in gone) {
        if (CGRectGetMinY(each.CGRectValue) < top - 0.5) lift += each.CGRectValue.size.height;
    }
    if (!out && lift < 0.5) return given;
    UICollectionViewLayoutAttributes *moved = [given copy];
    CGRect frame = moved.frame;
    frame.origin.y -= lift;
    moved.frame = frame;
    if (out) moved.alpha = 0;
    return moved;
}

static void adoptLayout(UICollectionView *list) {
    static char kAdoptedKey;
    UICollectionViewLayout *layout = list.collectionViewLayout;
    if (!layout || objc_getAssociatedObject(layout, &kAdoptedKey)) return;
    objc_setAssociatedObject(layout, &kAdoptedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class base = object_getClass(layout);
    NSString *name = [@"SGDrawer_" stringByAppendingString:NSStringFromClass(base)];
    if ([NSStringFromClass(base) hasPrefix:@"NSKVONotifying_"]) return;
    Class made = objc_getClass(name.UTF8String);
    if (!made) {
        made = objc_allocateClassPair(base, name.UTF8String, 0);
        if (!made) return;
        SEL inRect = @selector(layoutAttributesForElementsInRect:), item = @selector(layoutAttributesForItemAtIndexPath:);
        SEL extra = @selector(layoutAttributesForSupplementaryViewOfKind:atIndexPath:), decor = @selector(layoutAttributesForDecorationViewOfKind:atIndexPath:);
        SEL content = @selector(collectionViewContentSize);
        class_addMethod(made, inRect, imp_implementationWithBlock(^NSArray *(UICollectionViewLayout *me, CGRect rect) {
            NSArray<NSValue *> *gone = goneFrames(me, base);
            struct objc_super up = {me, base};
            rect.size.height += goneHeight(gone);
            NSArray<UICollectionViewLayoutAttributes *> *given = ((NSArray *(*)(struct objc_super *, SEL, CGRect))objc_msgSendSuper)(&up, inRect, rect);
            if (!gone.count) return given;
            NSMutableArray *all = [NSMutableArray arrayWithCapacity:given.count];
            for (UICollectionViewLayoutAttributes *each in given) [all addObject:lifted(each, gone)];
            return all;
        }), method_getTypeEncoding(class_getInstanceMethod(base, inRect)));
        class_addMethod(made, item, imp_implementationWithBlock(^UICollectionViewLayoutAttributes *(UICollectionViewLayout *me, NSIndexPath *path) {
            struct objc_super up = {me, base};
            return lifted(((id (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&up, item, path), goneFrames(me, base));
        }), method_getTypeEncoding(class_getInstanceMethod(base, item)));
        for (NSValue *boxed in @[[NSValue valueWithPointer:extra], [NSValue valueWithPointer:decor]]) {
            SEL kindAt = boxed.pointerValue;
            class_addMethod(made, kindAt, imp_implementationWithBlock(^UICollectionViewLayoutAttributes *(UICollectionViewLayout *me, NSString *kind, NSIndexPath *path) {
                struct objc_super up = {me, base};
                return lifted(((id (*)(struct objc_super *, SEL, id, id))objc_msgSendSuper)(&up, kindAt, kind, path), goneFrames(me, base));
            }), method_getTypeEncoding(class_getInstanceMethod(base, kindAt)));
        }
        class_addMethod(made, content, imp_implementationWithBlock(^CGSize(UICollectionViewLayout *me) {
            struct objc_super up = {me, base};
            CGSize size = ((CGSize (*)(struct objc_super *, SEL))objc_msgSendSuper)(&up, content);
            size.height = MAX(0, size.height - goneHeight(goneFrames(me, base)));
            return size;
        }), method_getTypeEncoding(class_getInstanceMethod(base, content)));
        objc_registerClassPair(made);
    }
    object_setClass(layout, made);
    SGLog(@"side menu: the list's layout (%@) closes up over the rows taken out", NSStringFromClass(base));
}

// The list sets each row's alpha back from its layout on every pass, so it is set here every time too.
static void fade(UIView *row, BOOL out) {
    BOOL was = objc_getAssociatedObject(row, &kTrimmedKey) != nil;
    if (out && row.alpha > 0) row.alpha = 0;
    if (out == was) return;
    if (!out) row.alpha = 1;
    row.userInteractionEnabled = !out;
    objc_setAssociatedObject(row, &kTrimmedKey, out ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// A label of the drawer's taking useless words is faded with its row the moment it takes them, not on the
// list's next pass: its row is the cell it is in, or, outside the list (Messages may be), the view under
// whatever holds several rows or most of the drawer.
static void fadeUselessLabel(UILabel *label) {
    UIView *root = sg_drawerRoot;
    if (!root || SGFlag(SGKeyDrawerUseless, NO) || !uselessText(label.text)) return;
    CGFloat tall = root.bounds.size.height * 0.5;
    UIView *row = nil;
    for (UIView *view = label; view && view != root; view = view.superview) {
        UIView *parent = view.superview;
        if (!parent) return;
        if ([parent isKindOfClass:UICollectionView.class] || [parent isKindOfClass:UIStackView.class]
            || parent == root || parent.bounds.size.height > tall) {
            row = view;
            break;
        }
    }
    if (!row) return;
    fade(row, YES);
    if ([row.superview isKindOfClass:UICollectionView.class]) [row.superview setNeedsLayout];
}

// A useless row is faded and its place given to the rows under it (adoptLayout). A row reused for something
// else is brought back.
static void trimDrawer(UICollectionView *list) {
    BOOL whole = SGFlag(SGKeyDrawerUseless, NO), changed = NO;
    if (!sg_gone) sg_gone = [NSMutableSet set];
    if (whole && sg_gone.count) {
        [sg_gone removeAllObjects];
        changed = YES;
    }
    for (UIView *row in list.subviews) {
        if (![row isKindOfClass:UICollectionReusableView.class]) continue;
        NSIndexPath *path = [row isKindOfClass:UICollectionViewCell.class] ? [list indexPathForCell:(UICollectionViewCell *)row] : nil;
        BOOL out = NO;
        if (!whole) {
            BOOL worded = rowHasText(row), known = path && [sg_gone containsObject:path];
            out = worded ? uselessRow(row) : known;
            if (path && worded && out != known) {
                if (out) [sg_gone addObject:path];
                else [sg_gone removeObject:path];
                changed = YES;
            }
        }
        fade(row, out);
    }
    if (!whole) adoptLayout(list);
    if (changed) [list.collectionViewLayout invalidateLayout];
}

// The drawer's Listening stats row opens the mod's own stats page: a control laid over that row, which a
// touch reaches before the list does, so Spotify's page is not opened under it.
@interface SGStatsCover : UIControl
@end

@implementation SGStatsCover

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = @"Listening stats";
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)open {
    UIViewController *owner = nil;
    for (UIResponder *r = self; r && !owner; r = r.nextResponder) {
        if ([r isKindOfClass:UIViewController.class]) owner = (UIViewController *)r;
    }
    UIViewController *presenting = owner.presentingViewController;
    if (presenting) {
        [presenting dismissViewControllerAnimated:YES completion:^{
            SGShowPage(navigationIn(presenting).topViewController ?: presenting, SGListeningStatsPage());
        }];
        return;
    }
    SGShowPage(owner, SGListeningStatsPage());
}

@end

static char kStatsCoverKey;

static BOOL statsRow(UIView *row) {
    __block BOOL found = NO;
    SGForEachView(row, ^(UIView *view) {
        if (found || ![view isKindOfClass:UILabel.class]) return;
        NSString *text = ((UILabel *)view).text;
        for (NSString *start in @[@"Stats d'écoute", @"Stats d’écoute", @"Listening stats", @"Listening Stats"]) {
            if ([text hasPrefix:start]) found = YES;
        }
    });
    return found;
}

// Spotify marks its stats row as new, with a dot and the word: the row opens the mod's page, which is not.
static void quietNew(UIView *row) {
    NSCharacterSet *around = [NSCharacterSet characterSetWithCharactersInString:@" \u00a0•·"];
    SGForEachView(row, ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class]) {
            UILabel *label = (UILabel *)view;
            NSString *text = label.text;
            NSString *bare = [text stringByTrimmingCharactersInSet:around].lowercaseString;
            if ([@[@"nouveau", @"new", @"nouveauté", @"neu", @"nuevo"] containsObject:bare]) {
                if (view.alpha > 0) view.alpha = 0;
                return;
            }
            NSRange dot = [text rangeOfString:@"•"];
            if (dot.location != NSNotFound && dot.location > 3) {
                label.text = [[text substringToIndex:dot.location] stringByTrimmingCharactersInSet:around];
            }
        } else if (!view.subviews.count && ![view isKindOfClass:UIImageView.class] && ![view isKindOfClass:UIControl.class]) {
            CGSize size = view.bounds.size;
            if (size.width >= 2 && size.width <= 10 && size.height >= 2 && size.height <= 10 && view.layer.cornerRadius > 0.5 && view.alpha > 0) view.alpha = 0;
        }
    });
}

static void coverStats(UICollectionView *list) {
    for (UIView *row in list.subviews) {
        if (![row isKindOfClass:UICollectionReusableView.class]) continue;
        SGStatsCover *cover = objc_getAssociatedObject(row, &kStatsCoverKey);
        if (!statsRow(row)) {
            [cover removeFromSuperview];
            continue;
        }
        quietNew(row);
        if (!cover) {
            cover = [SGStatsCover new];
            objc_setAssociatedObject(row, &kStatsCoverKey, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (cover.superview != row) [row addSubview:cover];
        else if (row.subviews.lastObject != cover) [row bringSubviewToFront:cover];
        if (!CGRectEqualToRect(cover.frame, row.bounds)) cover.frame = row.bounds;
    }
}

// Keep the drawer's plan badge and the SPMod settings row current as Spotify rebuilds its view.
// Spotify gives the drawer its grey again each time it opens: the light goes back behind it then too.
static void relightDrawer(UIViewController *drawer) {
    UIView *root = drawer.viewIfLoaded;
    if (!root || !SGRedesignedUI()) return;
    SGRAccentWashPlace(root);
    SGForEachView(root, ^(UIView *view) {
        if (![view isKindOfClass:UICollectionView.class] ||
            ![NSStringFromClass(view.class) containsString:@"SideDrawerListCollectionView"]) return;
        trimDrawer((UICollectionView *)view);
        if (view.superview) SGRAccentWashPlace(view.superview);
    });
}

%hook _TtC23SideDrawer_ListPageImpl18ListViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    relightDrawer((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    relightDrawer((UIViewController *)self);
    __weak UIViewController *weakSelf = (UIViewController *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ relightDrawer(weakSelf); });
}

- (void)viewDidLayoutSubviews {
    %orig;
    sg_drawerRoot = ((UIViewController *)self).view;
    // The redesign's light behind the drawer, as behind Home and the library.
    if (SGRedesignedUI()) SGRAccentWashPlace(sg_drawerRoot);
    updatePlanBadge(sg_drawerRoot);
    SGForEachView(sg_drawerRoot, ^(UIView *view) {
        if (![view isKindOfClass:UICollectionView.class] ||
            ![NSStringFromClass(view.class) containsString:@"SideDrawerListCollectionView"]) return;
        ensureDrawerRow((UICollectionView *)view);
    });
}
%end

// The lists lay out after their controllers and again whenever their content changes.
// Profile menu on (Liquid Glass): each row the drawer shows on a card of glass. A row taken out, or the
// whole switch off, has none. The account block's own grey is cleared so its glass shows.
static void glassDrawer(UICollectionView *list) {
    static char kDrawerCardKey;
    static BOOL logged;
    BOOL on = SGFlag(SGRKeyDrawerGlass, NO);
    NSUInteger cards = 0;
    for (UIView *row in list.subviews) {
        if (![row isKindOfClass:UICollectionReusableView.class] || [row isKindOfClass:SGModSettingsRow.class]) continue;
        CGSize size = row.bounds.size;
        BOOL wanted = on && row.alpha > 0.01 && size.height >= 30 && size.width > list.bounds.size.width * 0.5;
        if (wanted) {
            for (UIView *span in row.subviews) {
                CGFloat w = 0, a = 0;
                if ([span.backgroundColor getWhite:&w alpha:&a] && a > 0.3 && w < 0.3) span.backgroundColor = UIColor.clearColor;
            }
            cards++;
        }
        SGRGlassCard(row, &kDrawerCardKey, CGRectInset(row.bounds, 10, 4), MIN(22, size.height / 2 - 4), wanted);
    }
    if (on && cards && !logged) {
        logged = YES;
        SGLog(@"side menu: %lu rows on glass", (unsigned long)cards);
    }
}

%hook UICollectionView
- (void)layoutSubviews {
    %orig;
    // Every list of the app lays out through here, each frame of a scroll: what it is is told once.
    static char kKindKey;
    NSNumber *kind = objc_getAssociatedObject(self, &kKindKey);
    if (!kind) {
        kind = @([NSStringFromClass(self.class) containsString:@"SideDrawerListCollectionView"]);
        objc_setAssociatedObject(self, &kKindKey, kind, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    SGModSettingsRow *row = objc_getAssociatedObject(self, &kRowKey);
    BOOL drawerList = kind.boolValue;
    if (drawerList) {
        updatePlanBadge(self);
        trimDrawer(self);
        coverStats(self);
        // The redesign's light right behind the list, where the drawer's own grey is.
        if (SGRedesignedUI() && self.superview) SGRAccentWashPlace(self.superview);
    }
    if (drawerList && SGRedesignedUI()) glassDrawer(self);
    if (!row && drawerList)
        row = ensureDrawerRow(self);
    if (row && row.superview != self) [self addSubview:row];
    if (row) placeRow(self, row);
}
%end

%ctor {
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGSidebarBadgeTextDidChangeNotification object:nil queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) {
        if (sg_drawerRoot) updatePlanBadge(sg_drawerRoot);
    }];
    SGRequireClasses(@[@"_TtC21Settings_PlatformImpl26SettingsListViewController", @"_TtC23SideDrawer_ListPageImpl18ListViewController"]);
    SGRegisterPages();
    SGCheckSigningOnce();
}
