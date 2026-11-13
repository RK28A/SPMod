#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Pages.h"
#import "Redesigned/Kit/SGRGlassSettings.h"
#import "Shared/AlphaIndex/AlphaIndex.h"
#import "Shared/ArtistBlock/ArtistBlock.h"
#import "Shared/Concerts/Concerts.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/NightMode/NightMode.h"
#import "Settings/SGBackdrop.h"
#import "Shared/Fusion/Fusion.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsMeanings/Meanings.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/Fonts/Fonts.h"
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/Lossless/SGLossless.h"
#import "Shared/Navigation/KeyCommands.h"
#import "Shared/Player/PlayerSettings.h"
#import "Native/Appearance/Appearance.h"
#import "Native/Navbar/Navbar.h"
#import "Native/NowPlayingBar/NowPlayingBar.h"
#import "Native/Player/NowPlaying.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/LiveActivity/LiveActivity.h"
#import "Redesigned/Lyrics/LyricsText.h"
#import "Redesigned/Lyrics/LyricsLook.h"
#import "Redesigned/Home/Home.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Kit/SGRAccent.h"

NSString *const SGRedesignedUIInfo = @"SPMod's redesigned look, leaning towards Apple Music's style. It is not compatible with the legacy look's settings.\n\nThe legacy look gives you more freedom, yet still looks like Spotify.";
NSNotificationName const SGSidebarBadgeTextDidChangeNotification = @"spotifyglass.sidebarBadgeTextDidChange";

static NSString *sidebarBadgeText(void) {
    NSString *text = [NSUserDefaults.standardUserDefaults stringForKey:SGKeySidebarBadgeText];
    return text.length ? text : @"SPMod";
}

static SGModRow *sidebarBadgeTextRow(void) {
    SGModRow *row = SGStatActionRow(@"Sidebar badge text", @"Change the text shown in Spotify's sidebar badge",
        ^NSString *{ return sidebarBadgeText(); }, ^{
            UIViewController *top = SGTopController();
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Sidebar badge text"
                message:@"Leave the field empty to use SPMod." preferredStyle:UIAlertControllerStyleAlert];
            [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
                field.text = sidebarBadgeText();
                field.clearButtonMode = UITextFieldViewModeWhileEditing;
                field.returnKeyType = UIReturnKeyDone;
            }];
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
            [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                NSString *text = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (text.length) [NSUserDefaults.standardUserDefaults setObject:text forKey:SGKeySidebarBadgeText];
                else [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeySidebarBadgeText];
                [NSNotificationCenter.defaultCenter postNotificationName:SGSidebarBadgeTextDidChangeNotification object:nil];
            }]];
            [top presentViewController:alert animated:YES completion:nil];
        });
    row.refreshOn = SGSidebarBadgeTextDidChangeNotification;
    return SGWithSymbol(row, @"tag");
}

void SGSetRedesignedUI(BOOL on) {
    SGSetEnabled(SGKeyRedesign, on);
}

static void offerRestart(BOOL on) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restart Spotify"
        message:on ? @"The redesign takes over when Spotify starts again. Spotify closes now; open it again to see it." : @"Spotify's own look comes back when Spotify starts again. Spotify closes now; open it again to see it."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { SGRestartSpotify(); }]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// The style chosen under Background style, with its own settings: each style keeps its own.
static UIViewController *backdropTunePage(void) {
    NSArray<NSString *> *names = SGBackdropStyleNames();
    NSInteger style = MAX(0, MIN((NSInteger)names.count - 1, SGInt(SGKeyBackdropStyle, 0)));
    NSString *(^percent)(double) = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; };
    SGModRow *(^slider)(NSString *, NSString *, SGBackdropTune, double, double) = ^SGModRow *(NSString *title, NSString *note, SGBackdropTune what, double low, double high) {
        return SGSliderRow(title, note, low, high, 0.05, ^double { return SGBackdropTuneValue(what, style); },
                           ^(double value) { SGBackdropSetTune(what, style, value); }, percent);
    };
    SGModRow *reset = SGActionRow(@"Back to this style's own", @"Speed, brightness, colours and music as they came", ^{
        SGBackdropResetTune(style);
        [SGTopController().navigationController popViewControllerAnimated:YES];
    });
    return [[SGModPage alloc] initWithTitle:names[style] intro:nil sections:@[
        SGNotedSection(@"Motion", @[
            slider(@"Speed", @"How fast the style runs", SGBackdropTuneSpeed, 0.25, 2.5),
            slider(@"Reaction to music", @"How often and how hard it answers the beat: meteors, rings, bars, flashes", SGBackdropTuneMusic, 0, 2),
        ], @"At 0% the style ignores the music. Over 100% it answers harder, and Stars throws more meteors."),
        SGNotedSection(@"Look", @[
            slider(@"Brightness", @"How much of the style shows over the black", SGBackdropTuneGlow, 0.2, 1),
            slider(@"Colour spread", @"How far its other colours stray from the theme's", SGBackdropTuneSpread, 0, 1),
        ], @"At 0% the whole style is drawn in the theme's one colour. At 100% a red theme also shows orange and purple."),
        SGSection(nil, @[SGWithSymbol(reset, @"arrow.counterclockwise")]),
    ] footer:@"Each background style keeps its own settings."];
}

static SGModRow *unavailableRow(void) {
    SGModRow *row = SGStatActionRow(@"Redesigned UI", nil, ^NSString *{ return @"Needs iOS 26"; }, ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Redesigned UI"
            message:[NSString stringWithFormat:@"The redesign is built on Liquid Glass, which iOS 26 draws and no earlier version can. This phone runs iOS %@, so the mod gives you its legacy look instead: Spotify's own screens with everything else the mod adds on them.", UIDevice.currentDevice.systemVersion]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return SGWithSymbol(row, @"sparkles");
}

UIViewController *SGAppearanceSettingsPage(void) {
    NSMutableArray<SGModRow *> *rows = [NSMutableArray array];
    if (!SGRedesignAvailable()) {
        [rows addObject:unavailableRow()];
        [rows addObjectsFromArray:SGNativeAppearanceRows()];
    } else {
        SGModRow *redesign = SGOptionRow(@"Redesigned UI", nil, SGKeyRedesign);
        redesign.glows = YES;
        redesign.info = SGRedesignedUIInfo;
        redesign.changed = ^(BOOL on) {
            SGSetRedesignedUI(on);
            offerRestart(on);
        };
        [rows addObject:SGWithSymbol(redesign, @"sparkles")];
        if (SGRedesignedUIStored()) {
            [rows addObject:SGWithSymbol(SGPageRow(@"Liquid Glass", ^UIViewController *{ return SGRGlassSettingsPage(); }), @"drop.halffull")];
            [rows addObjectsFromArray:SGRAppearanceRows()];
            [rows addObject:SGRHomeStyleRow()];
            [rows addObject:SGRHomeTopPicksRow()];
            [rows addObjectsFromArray:SGRHomeGradientRows()];
        } else {
            [rows addObjectsFromArray:SGNativeAppearanceRows()];
        }
    }
    [rows addObjectsFromArray:SGAppFontRows()];
    [rows addObject:SGWithSymbol(SGPageRow(@"Night mode", ^UIViewController *{ return SGNightModeSettingsPage(); }), @"moon.stars")];
    SGModRow *backdrop = SGHideRow(@"Animated background", @"A moving background behind the mod's menus", SGKeyBackdrop);
    backdrop.changed = ^(BOOL on) { [NSNotificationCenter.defaultCenter postNotificationName:SGBackdropDidChangeNotification object:nil]; };
    SGModRow *backdropStyle = SGChoiceRow(@"Background style", nil, SGKeyBackdropStyle, SGBackdropStyleNames(), 0);
    SGModRow *backdropColor = SGChoiceRow(@"Background colour", nil, SGKeyBackdropSource, @[@"Follows the song", @"Accent colour"], 0);
    backdropColor.choiceNotes = @[@"Takes the colour of the cover playing. A new song's colour comes in once the animation ends its loop.",
                                  @"Keeps the accent colour chosen above."];
    SGModRow *backdropRate = SGChoiceRow(@"Background frame rate", nil, SGKeyBackdropRate, @[@"30 a second", @"60 a second", @"As fast as the screen"], 0);
    backdropRate.choiceNotes = @[@"The coolest on the phone and the lightest on the battery.", @"Smoother, a little warmer.",
                                 @"Up to 120 a second on a ProMotion screen: the smoothest, and the warmest."];
    for (SGModRow *row in @[backdropStyle, backdropColor, backdropRate]) {
        row.visible = ^BOOL { return SGHidden(SGKeyBackdrop); };
        row.chosen = ^(NSInteger index) { [NSNotificationCenter.defaultCenter postNotificationName:SGBackdropDidChangeNotification object:nil]; };
    }
    SGModRow *backdropTune = SGPageRow(@"Customise this style", ^UIViewController *{ return backdropTunePage(); });
    backdropTune.visible = ^BOOL { return SGHidden(SGKeyBackdrop); };
    [rows addObject:SGWithSymbol(backdrop, @"circle.hexagongrid")];
    [rows addObject:SGWithSymbol(backdropStyle, @"sparkles")];
    [rows addObject:SGWithSymbol(backdropColor, @"eyedropper")];
    [rows addObject:SGWithSymbol(backdropTune, @"slider.horizontal.3")];
    [rows addObject:SGWithSymbol(backdropRate, @"speedometer")];
    [rows addObject:sidebarBadgeTextRow()];
    SGModSection *section = SGNotedSection(nil, rows, @"Some changes apply after you restart Spotify.");
    return [[SGModPage alloc] initWithTitle:@"Appearance" intro:nil sections:@[section] footer:nil];
}

UIViewController *SGNavbarPage(void) {
    return SGRedesignedUIStored() ? SGRNavbarSettingsPage() : SGNavbarSettingsPage();
}

// Pronunciation, translation, word sweeping and line meanings exist only in the redesign's lyrics.
UIViewController *SGLyricsSettingsPage(void) {
    BOOL redesigned = SGRedesignedUIStored();
    NSMutableArray<SGModRow *> *more = [NSMutableArray arrayWithObject:SGLockScreenLyricsRow()];
    if (!redesigned) [more insertObject:SGGlassLyricsRow() atIndex:0];
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGLyricsSourcesSection(redesigned)];
    if (redesigned) {
        SGModRow *landscape = SGSwitchRow(@"Landscape lyrics", @"Show lyrics beside the player controls", SGRKeyLandscapeLyrics);
        landscape.changed = ^(BOOL on) { SGRPlayerLyricsOrientationChanged(); };
        [sections addObject:SGSection(@"Display", @[landscape,
            SGLyricsWordTimingRow(), SGLyricsRomanisedRow(), SGLyricsPronunciationScriptRow(), SGRLyricsFuriganaRow(), SGLyricsDelayRow(),
            SGRLyricsTextSizesRow(), SGLyricsTranslationLanguageRow(), SGLyricsMeaningsRow(), SGLyricsMeaningMarkersRow()])];
        [sections addObject:SGSection(@"Translation", @[SGTranslateEverySongRow(), SGGeminiKeyRow(), SGSavedTranslationsRow()])];
    }
    [sections addObject:SGLyricsOfflineCacheSection()];
    [sections addObject:SGSection(nil, more)];
    // The redesign's page leads with a live preview of the lyrics, a glass pill to search the song it plays,
    // the presets and the sliders and font behind the Adjust button; every change applies to the app's lyrics at once.
    if (redesigned) return SGRLyricsSettingsPage(@"Lyrics", SGRestartNote, sections);
    return [[SGModPage alloc] initWithTitle:@"Lyrics" intro:SGRestartNote sections:sections footer:nil];
}

UIViewController *SGPlayerSettingsPage(void) {
    SGModRow *blocked = SGPageRow(@"Blocked artists", ^UIViewController *{ return SGArtistBlockSettingsPage(); });
    blocked.value = ^NSString *{
        return SGFlag(SGKeyArtistBlock, NO) ? @(SGBlockedArtists().count).stringValue : @"Off";
    };
    BOOL native = !SGRedesignedUIStored();

    // AirPods gestures has its own row on the Mod Settings root, so it is not repeated here.
    NSMutableArray<SGModSection *> *sections = [NSMutableArray arrayWithObject:SGSection(nil, @[
        SGWithSymbol(SGPageRow(@"Gestures", ^UIViewController *{ return SGGesturesSettingsPage(); }), @"hand.tap"),
        SGWithSymbol(blocked, @"person.crop.circle.badge.xmark"),
        SGWithSymbol(SGKeyboardShortcutsRow(), @"command"),
        SGWithImage(SGPageRow(@"Playlist Fusion", ^UIViewController *{ return SGFusionSettingsPage(); }), SGFusionIcon(SGFusionGlyphMerge, 18)),
    ])];
    NSMutableArray<SGModRow *> *pages = [NSMutableArray array];
    if (native) {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing bar", ^UIViewController *{ return SGNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
        [pages addObject:SGWithSymbol(SGPageRow(@"Queue & devices", ^UIViewController *{ return SGQueueSettingsPage(); }), @"text.line.first.and.arrowtriangle.forward")];
    } else {
        [pages addObject:SGWithSymbol(SGPageRow(@"Now playing", ^UIViewController *{ return SGRNowPlayingBarSettingsPage(); }), @"rectangle.bottomthird.inset.filled")];
    }
    [sections addObject:SGSection(nil, pages)];
    // Playlists and artist pages: the alphabet index works with either look, the concerts card is the redesign's.
    NSMutableArray<SGModRow *> *browsing = [NSMutableArray arrayWithObject:SGWithSymbol(SGAlphaIndexRow(), @"textformat.abc")];
    if (!native) {
        [browsing addObject:SGWithSymbol(SGSwitchRow(@"Upcoming concerts", @"Show an artist's tour dates under their name", SGKeyConcerts), @"ticket")];
    }
    [sections addObject:SGNotedSection(@"Browsing", browsing, @"Applies after you restart Spotify.")];
    [sections addObject:SGNotedSection(@"Lossless", @[
        SGOptionRow(@"Lossless files", @"Play matching FLAC or ALAC files instead of Spotify's stream", SGKeyLossless),
    ], @"Put matching files in Files › Spotify › Lossless. Applies after you restart Spotify.")];
    if (!native) return SGRPlayerSettingsPage(sections);
    if (native) [sections addObjectsFromArray:SGNativePlayerScreenSections()];
    return [[SGModPage alloc] initWithTitle:@"Player" intro:SGRestartNote sections:sections footer:nil];
}
