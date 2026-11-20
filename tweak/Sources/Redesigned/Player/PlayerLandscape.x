// Player redesign: the lyrics turn sideways with the phone onto a landscape screen of their own. The cover
// is on the left with the title, the artist and the controls under it, and the lines are on the right.
// The controls fade after a few seconds without a touch and come back at a tap, as in the player: the
// tap that brings them back lands on a clear shield over the screen, so it never seeks. The button beside
// the title turns the screen back to portrait, as VoiceOver's escape does, for a phone held flat or on its
// side; the screen stays shut then until the phone has stood upright again.
//
// Spotify's iPhone Info.plist allows portrait only, and UIKit asks the app delegate's
// -application:supportedInterfaceOrientationsForWindow: in its place where there is one. So the delegate
// answers landscape for this screen's own window and portrait for every other, and the scene is asked to
// turn while the window is up. Spotify's own windows never turn.
#import <objc/runtime.h>
#import <AVFoundation/AVFoundation.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Player.h"

static const CGFloat kSide = 32, kCoverGap = 16, kControlSide = 44, kColumnShare = 0.5;
static const NSTimeInterval kLandscapeRest = 4;
static const CGFloat kScrub = 36;   // the time bar and its two times under it

static UIWindow *sg_window;
// Shut from the screen: turning the phone again does not reopen it until it has stood upright.
static BOOL sg_shut;

#pragma mark - the screen

@interface SGRLandscapeLyricsController : UIViewController <SGPlayerStateObserver>
@end

@implementation SGRLandscapeLyricsController {
    SGRArtworkField *_field;
    UIImageView *_cover;
    SGMarqueeLabel *_title, *_artist;
    UIStackView *_controls;
    UIButton *_play, *_close;
    UIView *_stage;   // the lines' own view: the karaoke view dims every sibling it has
    SGRKaraokeView *_lyrics;
    NSTimer *_rest;
    BOOL _withLines;                 // the lyrics column is there; without it the cover and controls share the screen
    UITapGestureRecognizer *_hide;   // only while the controls are up
    UIView *_shield;                 // only while they are not: the touch that brings them back
    UISlider *_scrub;
    UILabel *_elapsed, *_remaining;
    BOOL _scrubbing;
    NSTimer *_clock;
    AVQueuePlayer *_clipPlayer;      // the player's clip, looping in the cover (SGRPlayerMotionFile)
    AVPlayerLooper *_looper;
    AVPlayerLayer *_clipLayer;
    NSURL *_clipFile;
}

// Portrait once the screen is on its way out, or the scene could not turn back while it fades.
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return sg_window.rootViewController == self ? UIInterfaceOrientationMaskLandscape : UIInterfaceOrientationMaskPortrait;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

// A glyph in a 44pt square, so the touch is as large as the default control whatever the glyph's size.
static UIButton *controlButton(NSString *symbol, CGFloat size, NSString *label, SEL action, id target) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    button.accessibilityLabel = label;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintEqualToConstant:kControlSide].active = YES;
    [button.heightAnchor constraintEqualToConstant:kControlSide].active = YES;
    return button;
}

// The title and the artist at the phone's text size, capped where the column still holds a cover.
- (void)applyFonts {
    _title.font = SGRFont(UIFontTextStyleTitle3, UIFontWeightBold, UIContentSizeCategoryExtraExtraExtraLarge);
    _artist.font = SGRFont(UIFontTextStyleCallout, UIFontWeightRegular, UIContentSizeCategoryExtraExtraExtraLarge);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self applyFonts];
    [self.view setNeedsLayout];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    // The player's own field behind the screen, so the colors carry over from the portrait player.
    _field = [[SGRArtworkField alloc] initWithFrame:self.view.bounds];
    _field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _field.showsBackdrop = YES;
    _field.fluid = YES;
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (art) [_field setArtwork:art identity:identity animated:NO];
    [self.view addSubview:_field];

    _cover = [UIImageView new];
    _cover.contentMode = UIViewContentModeScaleAspectFill;
    _cover.clipsToBounds = YES;
    _cover.layer.cornerRadius = SGRRadiusArtwork;
    _cover.layer.cornerCurve = kCACornerCurveContinuous;
    _cover.image = art;
    [self.view addSubview:_cover];

    // A title or artist too long for the column scrolls, as the player's own do.
    _title = [SGMarqueeLabel new];
    _title.textColor = UIColor.whiteColor;
    _artist = [SGMarqueeLabel new];
    _artist.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self applyFonts];
    [self.view addSubview:_title];
    [self.view addSubview:_artist];
    // Where the Music app keeps a song's ⋯: the way back to the player, for a phone that is not turned back.
    _close = controlButton(@"arrow.down.right.and.arrow.up.left", 17, @"Exit full screen", @selector(turnBack), self);
    [self.view addSubview:_close];

    _play = controlButton(@"pause.fill", 30, @"Pause", @selector(togglePlay), self);
    _controls = [[UIStackView alloc] initWithArrangedSubviews:@[
        controlButton(@"backward.fill", 24, @"Previous track", @selector(previous), self), _play,
        controlButton(@"forward.fill", 24, @"Next track", @selector(next), self),
    ]];
    _controls.distribution = UIStackViewDistributionEqualSpacing;
    _controls.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:_controls];

    _stage = [UIView new];
    [self.view addSubview:_stage];
    _lyrics = [[SGRKaraokeView alloc] initWithFrame:CGRectZero];
    _lyrics.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _lyrics.extrasEnabled = SGEnabled(SGRKeyPlayerTranslateButton);
    [_stage addSubview:_lyrics];
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _lyrics.browsingBegan = ^{ [weakSelf rest]; };

    _hide = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rest)];
    [self.view addGestureRecognizer:_hide];
    _shield = [[UIView alloc] initWithFrame:self.view.bounds];
    _shield.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _shield.accessibilityElementsHidden = YES;
    [_shield addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    [_shield addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(wake)]];
    _scrub = [UISlider new];
    _scrub.minimumTrackTintColor = UIColor.whiteColor;
    _scrub.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.25];
    [_scrub setThumbImage:[self thumb] forState:UIControlStateNormal];
    _scrub.accessibilityLabel = @"Position";
    [_scrub addTarget:self action:@selector(scrubMoved) forControlEvents:UIControlEventValueChanged];
    [_scrub addTarget:self action:@selector(scrubEnded) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.view addSubview:_scrub];
    _elapsed = [UILabel new];
    _remaining = [UILabel new];
    for (UILabel *label in @[_elapsed, _remaining]) {
        label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        label.textColor = [UIColor colorWithWhite:1 alpha:0.6];
        [self.view addSubview:label];
    }
    _remaining.textAlignment = NSTextAlignmentRight;
    SGAddPlayerStateObserver(self);
    [self playerStateDidChange:SGPlayerState()];
    // The clip stops decoding while the app is not in front (locked, another app); it picks up after.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clipRests) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(clipWakes) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(artworkChanged)
                                               name:SGRNowPlayingArtworkDidChangeNotification object:nil];
    // The shield is hidden from VoiceOver, so turning it on brings the controls back and keeps them.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(wake)
                                               name:UIAccessibilityVoiceOverStatusDidChangeNotification object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_rest invalidate];
    [_clock invalidate];
    [_clipPlayer pause];
}

- (void)clipRests {
    [_clipPlayer pause];
    [_clock invalidate];
    _clock = nil;
}

- (void)clipWakes {
    if (!self.view.window) return;
    [self updateClip:SGPlayerState().isPaused];
    if (_clock) return;
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _clock = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    _clock.tolerance = 0.1;
}

- (UIImage *)thumb {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(14, 14)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.whiteColor setFill];
        [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 1, 12, 12)] fill];
    }];
}

static NSString *clockText(double seconds) {
    long total = lround(MAX(0, seconds));
    return [NSString stringWithFormat:@"%ld:%02ld", total / 60, total % 60];
}

// Twice a second while the screen is up; a drag holds it.
- (void)tick {
    SPTPlayerState *state = SGPlayerState();
    double length = state.duration;
    // The clip is found a moment after the track changes: it comes in on the next beat.
    NSURL *file = SGRPlayerMotionFile();
    if (!(file == _clipFile || [file isEqual:_clipFile])) [self updateClip:state.isPaused];
    if (_scrubbing || length <= 0) return;
    double at = MIN(length, MAX(0, state.position));
    _scrub.value = at / length;
    _elapsed.text = clockText(at);
    _remaining.text = [@"-" stringByAppendingString:clockText(length - at)];
}

- (void)scrubMoved {
    _scrubbing = YES;
    double length = SGPlayerState().duration;
    _elapsed.text = clockText(_scrub.value * length);
    _remaining.text = [@"-" stringByAppendingString:clockText(length - _scrub.value * length)];
    [self restartRest];
}

- (void)scrubEnded {
    double length = SGPlayerState().duration;
    if (_scrubbing && length > 0) {
        [SGPlaybackPlayer() seekTo:_scrub.value * length];
        SGDebug(@"redesign player: landscape seek to %.0f s", _scrub.value * length);
    }
    _scrubbing = NO;
}

// The player's own clip in the cover, muted and looping, paused with the song.
- (void)updateClip:(BOOL)paused {
    NSURL *file = SGRPlayerMotionFile();
    if (!(file == _clipFile || [file isEqual:_clipFile])) {
        _clipFile = file;
        [_clipPlayer pause];
        [_clipLayer removeFromSuperlayer];
        _clipPlayer = nil;
        _looper = nil;
        _clipLayer = nil;
        if (file) {
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:file];
            _clipPlayer = [AVQueuePlayer new];
            _clipPlayer.muted = YES;
            _clipPlayer.preventsDisplaySleepDuringVideoPlayback = NO;
            _looper = [AVPlayerLooper playerLooperWithPlayer:_clipPlayer templateItem:item];
            _clipLayer = [AVPlayerLayer playerLayerWithPlayer:_clipPlayer];
            _clipLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            _clipLayer.frame = _cover.bounds;
            [_cover.layer addSublayer:_clipLayer];
        }
        SGDebug(@"redesign player: landscape clip %@", file ? file.lastPathComponent : @"none, the cover shows");
    }
    if (paused) [_clipPlayer pause];
    else [_clipPlayer play];
}

- (BOOL)wantsLines {
    return SGEnabled(SGRKeyLandscapeLyrics) && SGEnabled(SGRKeyLyricsLandscape) && SGRPlayerLyricsAvailable();
}

// Without lyrics: a large cover on the left, the title, the artist and the controls centred on the right.
- (void)layoutWithoutLines:(CGRect)safe {
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat side = MIN(safe.size.height - 2 * kSide, round(safe.size.width * 0.46));
    CGFloat left = CGRectGetMinX(safe) + kSide;
    _cover.frame = CGRectMake(left, CGRectGetMidY(safe) - side / 2, side, side);
    CGFloat columnLeft = CGRectGetMaxX(_cover.frame) + 2 * kSide;
    CGFloat width = CGRectGetMaxX(safe) - kSide - columnLeft;
    CGFloat block = titleHeight + artistHeight + kCoverGap * 2 + kScrub + kCoverGap + kControlSide;
    CGFloat top = CGRectGetMidY(safe) - block / 2;
    _title.frame = CGRectMake(columnLeft, top, width - kControlSide, titleHeight);
    _artist.frame = CGRectMake(columnLeft, CGRectGetMaxY(_title.frame), width - kControlSide, artistHeight);
    _close.frame = CGRectMake(columnLeft + width - kControlSide + 12, top + (titleHeight + artistHeight - kControlSide) / 2, kControlSide, kControlSide);
    CGFloat controlsWidth = MIN(width, 260);
    _controls.frame = CGRectMake(columnLeft + (width - controlsWidth) / 2, CGRectGetMaxY(_artist.frame) + 2 * kCoverGap, controlsWidth, kControlSide);
    _stage.frame = CGRectZero;
    [self placeScrubAt:CGRectGetMaxY(_artist.frame) + kCoverGap / 2 left:columnLeft width:width];
    _controls.frame = CGRectMake(columnLeft + (width - controlsWidth) / 2, CGRectGetMaxY(_scrub.frame) + 16 + kCoverGap / 2, controlsWidth, kControlSide);
    [self placeClip];
}

- (void)placeScrubAt:(CGFloat)top left:(CGFloat)left width:(CGFloat)width {
    _scrub.frame = CGRectMake(left, top, width, 20);
    _elapsed.frame = CGRectMake(left, CGRectGetMaxY(_scrub.frame), width / 2, 16);
    _remaining.frame = CGRectMake(left + width / 2, CGRectGetMaxY(_scrub.frame), width / 2, 16);
}

- (void)placeClip {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _clipLayer.frame = _cover.bounds;
    [CATransaction commit];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    BOOL withLines = [self wantsLines];
    if (withLines != _withLines) SGDebug(@"redesign player: landscape %@", withLines ? @"with lyrics" : @"without lyrics");
    _withLines = withLines;
    _stage.hidden = !withLines;
    if (!withLines) {
        [self layoutWithoutLines:safe];
        return;
    }
    // The left half: a large cover with the title, time bar and controls beside it; the lyrics on the right half.
    CGFloat half = round(safe.size.width * kColumnShare);
    CGFloat left = CGRectGetMinX(safe) + kSide;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistHeight = ceil(_artist.font.lineHeight);
    CGFloat room = half - kSide;
    CGFloat side = MIN(safe.size.height - 2 * kSide, room * 0.5);
    CGFloat columnLeft = left + side + 24;
    CGFloat width = room - side - 24;
    if (width < 150) {
        side = MAX(120, room - 24 - 150);
        columnLeft = left + side + 24;
        width = room - side - 24;
    }
    _cover.frame = CGRectMake(left, CGRectGetMidY(safe) - side / 2, side, side);
    CGFloat block = titleHeight + artistHeight + kCoverGap + kScrub + kCoverGap + kControlSide;
    CGFloat top = CGRectGetMidY(safe) - block / 2;
    _title.frame = CGRectMake(columnLeft, top, width - kControlSide + 8, titleHeight);
    _artist.frame = CGRectMake(columnLeft, CGRectGetMaxY(_title.frame), width - kControlSide + 8, artistHeight);
    _close.frame = CGRectMake(columnLeft + width - kControlSide + 12, top + (titleHeight + artistHeight - kControlSide) / 2, kControlSide, kControlSide);
    [self placeScrubAt:CGRectGetMaxY(_artist.frame) + kCoverGap left:columnLeft width:width];
    CGFloat controlsWidth = MIN(width, 220);
    _controls.frame = CGRectMake(columnLeft + (width - controlsWidth) / 2, CGRectGetMaxY(_scrub.frame) + 16 + kCoverGap, controlsWidth, kControlSide);
    [self placeClip];
    CGFloat linesLeft = CGRectGetMinX(safe) + half + 8;
    _stage.frame = CGRectMake(linesLeft, CGRectGetMinY(safe), CGRectGetMaxX(safe) - linesLeft, safe.size.height);
    _lyrics.frame = _stage.bounds;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self restartRest];
    [_clock invalidate];
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _clock = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
    _clock.tolerance = 0.1;
    [self tick];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_clock invalidate];
    _clock = nil;
    [_clipPlayer pause];
}

// The window comes up clear and fades in as the scene turns, so the screen is never seen laid out upright.
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    UIWindow *window = self.view.window;
    if (!window || window != sg_window || size.width <= size.height) return;
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        window.alpha = 1;
    } completion:nil];
}

- (void)artworkChanged {
    NSString *identity = nil;
    UIImage *art = SGRNowPlayingArtwork(NULL, &identity);
    if (!art) return;
    // On the field's clock, so the cover and the colors behind it change as one.
    UIImageView *cover = _cover;
    [UIView transitionWithView:cover duration:SGRCrossfade options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ cover.image = art; } completion:nil];
    [_field setArtwork:art identity:identity animated:YES];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    if (!state) return;
    _title.text = state.track.trackTitle;
    _artist.text = state.track.artistName;
    if ([self wantsLines] != _withLines) {
        [self.view setNeedsLayout];
        [UIView animateWithDuration:0.3 animations:^{ [self.view layoutIfNeeded]; }];
    }
    [_play setImage:[UIImage systemImageNamed:state.isPaused ? @"play.fill" : @"pause.fill" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:30 weight:UIImageSymbolWeightBold]] forState:UIControlStateNormal];
    _play.accessibilityLabel = state.isPaused ? @"Play" : @"Pause";
    _field.motionHeld = state.isPaused;
    [self updateClip:state.isPaused];
    [self tick];
    // A pause brings the controls back and keeps them; playing again, from here or anywhere, starts the
    // clock. The tap on the play button cannot: the state saying so arrives a beat after it.
    if (state.isPaused) [self setControlsShown:YES];
    else if (!_rest && !_shield.superview) [self restartRest];
}

#pragma mark - controls

- (id<SPTPlayer>)player {
    id player = SGKaraokePlayer();
    return [player conformsToProtocol:@protocol(SPTPlayer)] || [player respondsToSelector:@selector(pause:)] ? player : nil;
}

- (void)togglePlay {
    id<SPTPlayer> player = self.player;
    if (SGPlayerState().isPaused) [player resume:nil];
    else [player pause:nil];
    [self restartRest];
}

- (void)previous {
    [self.player skipToPreviousTrackWithOptions:nil];
    [self restartRest];
}

- (void)next {
    [self.player skipToNextTrackWithOptions:nil];
    [self restartRest];
}

- (void)turnBack {
    sg_shut = YES;
    SGRPlayerShowLandscape(NO);
}

// VoiceOver's two-finger scrub.
- (BOOL)accessibilityPerformEscape {
    [self turnBack];
    return YES;
}

// The lines on their own, unless VoiceOver needs the controls to be there.
- (void)rest {
    if (!UIAccessibilityIsVoiceOverRunning()) [self setControlsShown:NO];
}

- (void)wake {
    [self setControlsShown:YES];
}

- (void)setControlsShown:(BOOL)shown {
    [_rest invalidate];
    _rest = nil;
    _hide.enabled = shown;
    if (shown) [_shield removeFromSuperview];
    else if (!_shield.superview) {
        _shield.frame = self.view.bounds;
        [self.view addSubview:_shield];
    }
    // Back at a tap with the Kit's response, from where a fade out is; they go with the slow fade, as the
    // portrait player's do (PlayerLyrics.x).
    SGRAnimate(shown ? SGRMotionRespond : SGRMotionFade, ^{
        for (UIView *view in @[self->_controls, self->_close, self->_title, self->_artist, self->_scrub, self->_elapsed, self->_remaining]) view.alpha = shown ? 1 : 0;
        self->_lyrics.extrasHidden = !shown;
    }, nil);
    if (shown) [self restartRest];
}

- (void)restartRest {
    [_rest invalidate];
    _rest = nil;
    if (!_withLines || !SGEnabled(SGRKeyLyricsLandscapeAutoHide) || SGPlayerState().isPaused || UIAccessibilityIsVoiceOverRunning()) return;
    __weak SGRLandscapeLyricsController *weakSelf = self;
    _rest = [NSTimer scheduledTimerWithTimeInterval:kLandscapeRest repeats:NO block:^(NSTimer *timer) {
        // A sheet over the lines (a line's meanings) keeps them up, and the clock runs again behind it.
        SGRLandscapeLyricsController *strongSelf = weakSelf;
        if (strongSelf.presentedViewController) [strongSelf restartRest];
        else [strongSelf rest];
    }];
}

@end

#pragma mark - turning

static UIInterfaceOrientationMask (*sg_origOrientations)(id, SEL, UIApplication *, UIWindow *);

static UIInterfaceOrientationMask orientationsFor(id self, SEL _cmd, UIApplication *application, UIWindow *window) {
    if (window && window == sg_window) return UIInterfaceOrientationMaskLandscape;
    return sg_origOrientations ? sg_origOrientations(self, _cmd, application, window) : UIInterfaceOrientationMaskPortrait;
}

// The delegate's own answer stays for every window but the landscape one; one that has none answers
// portrait, which is what the Info.plist said.
static void answerForOrientations(void) {
    static BOOL done;
    id delegate = UIApplication.sharedApplication.delegate;
    if (done || !delegate) return;
    done = YES;
    SEL selector = @selector(application:supportedInterfaceOrientationsForWindow:);
    Method method = class_getInstanceMethod([delegate class], selector);
    if (method) sg_origOrientations = (void *)method_setImplementation(method, (IMP)orientationsFor);
    else class_addMethod([delegate class], selector, (IMP)orientationsFor, "Q@:@@");
    SGLog(@"redesign player: landscape lyrics answer for %@ (%@)", NSStringFromClass([delegate class]), method ? @"its own answer kept" : @"portrait otherwise");
}

// A landscape window still clear when no turn is coming to fade it in.
static void reveal(UIWindow *window) {
    if (window && window == sg_window && window.alpha < 1) SGRAnimate(SGRMotionFade, ^{ window.alpha = 1; }, nil);
}

static void requestOrientations(UIWindowScene *scene, UIInterfaceOrientationMask mask) {
    __weak UIWindow *window = sg_window;
    if (@available(iOS 16.0, *)) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
        [scene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
            SGLog(@"redesign player: the scene did not turn: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{ reveal(window); });
        }];
    }
}

void SGRPlayerShowLandscape(BOOL show) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    if (show && !sg_window) {
        answerForOrientations();
        sg_window = [[UIWindow alloc] initWithWindowScene:scene];
        sg_window.windowLevel = UIWindowLevelNormal + 1;
        // The window is the mod's own, so what it presents (Sing's alerts, a line's meanings) is dark too.
        sg_window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        sg_window.alpha = 0;
        sg_window.rootViewController = [SGRLandscapeLyricsController new];
        [sg_window makeKeyAndVisible];
        requestOrientations(scene, UIInterfaceOrientationMaskLandscape);
        if (UIInterfaceOrientationIsLandscape(scene.interfaceOrientation)) reveal(sg_window);
        SGLog(@"redesign player: the lyrics turn sideways");
    } else if (!show && sg_window) {
        UIWindow *window = sg_window;
        sg_window = nil;
        window.userInteractionEnabled = NO;
        // A sheet up over the lines (a line's meanings) goes with them, or it would be left on a hidden window.
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        if (@available(iOS 16.0, *)) [window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        requestOrientations(scene, UIInterfaceOrientationMaskPortrait);
        // Faded out as the scene turns back; the player is key again once it is gone, unless the lines came
        // back meanwhile.
        SGRAnimate(SGRMotionFade, ^{ window.alpha = 0; }, ^(BOOL finished) {
            window.hidden = YES;
            if (sg_window) return;
            for (UIWindow *other in scene.windows) {
                if (other != window && !other.hidden && other.windowLevel == UIWindowLevelNormal) {
                    [other makeKeyWindow];
                    break;
                }
            }
        });
        SGLog(@"redesign player: the lyrics turn back");
    }
}

static void orientationChanged(void) {
    UIDeviceOrientation orientation = UIDevice.currentDevice.orientation;
    if (UIDeviceOrientationIsLandscape(orientation)) {
        BOOL lyrics = SGRPlayerLyricsOpen() && SGEnabled(SGRKeyLyricsLandscape) && SGEnabled(SGRKeyLandscapeLyrics);
        BOOL player = SGRPlayerIsVisible() && SGEnabled(SGRKeyPlayerLandscape);
        SGDebug(@"redesign player: sideways (lyrics %d, player %d, shut %d)", lyrics, player, sg_shut);
        if (!sg_shut && (lyrics || player)) SGRPlayerShowLandscape(YES);
    } else if (orientation == UIDeviceOrientationPortrait) {
        sg_shut = NO;
        SGRPlayerShowLandscape(NO);
    }
}

void SGRPlayerLandscapeLyricsChanged(void) {
    UIView *view = sg_window.rootViewController.viewIfLoaded;
    if (!view) return;
    [view setNeedsLayout];
    [UIView animateWithDuration:0.3 animations:^{ [view layoutIfNeeded]; }];
}

void SGRPlayerLyricsOrientationChanged(void) {
    orientationChanged();
}

%ctor {
    if (!SGRedesignedUI()) return;
    SGDebug(@"module Redesigned/Player/PlayerLandscape.x on");
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        [NSNotificationCenter.defaultCenter addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) { orientationChanged(); }];
    });
}
