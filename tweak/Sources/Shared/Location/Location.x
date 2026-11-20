// Changing the account's country from the app, without a page on screen. The account page (spotify.com/account/
// profile) loads in a web view of the mod's that nobody sees; a script picks the country in its country list
// and presses its save button, and a banner says how it went. Only when the page asks to sign in does it come
// up, once: its session is kept in the keychain (pw.spoti.spmod.settings / web-session), so a reinstall finds
// it again. Spotify only offers the country it places the phone in (by its network), so that is what
// "where I am" means: the market in the page's own address (/ch-fr/ → CH). Every step goes to the log.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import <Security/Security.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "Settings/SGModPage.h"
#import "Location.h"

static NSString *const kProfilePage = @"https://www.spotify.com/account/profile/";

NSString *SGLocationDeviceCountry(void) {
    NSString *code = [NSLocale.currentLocale objectForKey:NSLocaleCountryCode];
    return [code isKindOfClass:NSString.class] ? code.uppercaseString : @"";
}

NSString *SGLocationName(NSString *code) {
    if (!code.length) return @"";
    return [NSLocale.currentLocale localizedStringForCountryCode:code] ?: code;
}

#pragma mark - the session, kept in the keychain

static NSDictionary *vaultQuery(void) {
    return @{(id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: @"pw.spoti.spmod.settings", (id)kSecAttrAccount: @"web-session"};
}

static void keepSession(WKWebView *web) {
    [web.configuration.websiteDataStore.httpCookieStore getAllCookies:^(NSArray<NSHTTPCookie *> *cookies) {
        NSMutableArray *kept = [NSMutableArray array];
        for (NSHTTPCookie *cookie in cookies) {
            if (![cookie.domain hasSuffix:@"spotify.com"]) continue;
            NSMutableDictionary *properties = [NSMutableDictionary dictionary];
            [cookie.properties enumerateKeysAndObjectsUsingBlock:^(NSHTTPCookiePropertyKey key, id value, BOOL *stop) {
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) properties[key] = value;
                else if ([value isKindOfClass:NSDate.class]) properties[key] = @([(NSDate *)value timeIntervalSince1970]);
            }];
            [kept addObject:properties];
        }
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:kept format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
        if (!data) return;
        NSDictionary *fresh = @{(id)kSecValueData: data, (id)kSecAttrAccessible: (id)kSecAttrAccessibleAfterFirstUnlock};
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)vaultQuery(), (__bridge CFDictionaryRef)fresh);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [vaultQuery() mutableCopy];
            [item addEntriesFromDictionary:fresh];
            status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        }
        SGDebug(@"location: %lu spotify.com cookies kept in the keychain (%d)", (unsigned long)kept.count, (int)status);
    }];
}

static void bringSession(WKWebView *web, void (^then)(void)) {
    NSMutableDictionary *ask = [vaultQuery() mutableCopy];
    ask[(id)kSecReturnData] = @YES;
    CFTypeRef found = NULL;
    NSArray *kept = nil;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)ask, &found) == errSecSuccess && found) {
        kept = [NSPropertyListSerialization propertyListWithData:(__bridge_transfer NSData *)found options:0 format:NULL error:nil];
    }
    if (![kept isKindOfClass:NSArray.class] || !kept.count) {
        then();
        return;
    }
    WKHTTPCookieStore *store = web.configuration.websiteDataStore.httpCookieStore;
    dispatch_group_t group = dispatch_group_create();
    NSUInteger brought = 0;
    for (NSDictionary *saved in kept) {
        NSMutableDictionary *properties = [saved mutableCopy];
        if ([properties[NSHTTPCookieExpires] isKindOfClass:NSNumber.class])
            properties[NSHTTPCookieExpires] = [NSDate dateWithTimeIntervalSince1970:[properties[NSHTTPCookieExpires] doubleValue]];
        NSHTTPCookie *cookie = [NSHTTPCookie cookieWithProperties:properties];
        if (!cookie) continue;
        brought++;
        dispatch_group_enter(group);
        [store setCookie:cookie completionHandler:^{ dispatch_group_leave(group); }];
    }
    SGDebug(@"location: %lu kept cookies put back", (unsigned long)brought);
    dispatch_group_notify(group, dispatch_get_main_queue(), then);
}

#pragma mark - the banner

static void banner(NSString *text) {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) window = w;
    if (!window) return;
    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UILabel *label = [UILabel new];
    label.text = text;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    CGFloat width = MIN(window.bounds.size.width - 32, 420);
    CGSize size = [label sizeThatFits:CGSizeMake(width - 32, CGFLOAT_MAX)];
    card.frame = CGRectMake((window.bounds.size.width - width) / 2, window.safeAreaInsets.top + 8, width, size.height + 28);
    label.frame = CGRectInset(card.bounds, 16, 14);
    [card.contentView addSubview:label];
    card.alpha = 0;
    card.transform = CGAffineTransformMakeTranslation(0, -20);
    [window addSubview:card];
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.85 initialSpringVelocity:0 options:0 animations:^{
        card.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    } completion:nil];
    [UIView animateWithDuration:0.3 delay:3.5 options:0 animations:^{ card.alpha = 0; } completion:^(BOOL done) { [card removeFromSuperview]; }];
}

#pragma mark - the page

static NSString *script(NSString *code, BOOL save) {
    return [NSString stringWithFormat:@
        "(function(code, save){"
        "var res = {url: location.href};"
        "var selects = Array.prototype.slice.call(document.querySelectorAll('select'));"
        "res.selects = selects.map(function(s){ return (s.id || s.name || '?') + ':' + s.options.length; }).join(',');"
        "function has(s){ return Array.prototype.some.call(s.options, function(o){ return (o.value||'').toUpperCase() === code; }); }"
        "var sel = selects.filter(function(s){ return /country|land|pays|region/i.test((s.id||'') + ' ' + (s.name||'')); })[0]"
        "  || selects.filter(has)[0];"
        "if (!sel) { res.found = false; return JSON.stringify(res); }"
        "res.found = true; res.before = sel.value;"
        "res.offered = Array.prototype.map.call(sel.options, function(o){ return o.value; }).slice(0, 12).join(',');"
        "var opt = Array.prototype.filter.call(sel.options, function(o){ return (o.value||'').toUpperCase() === code; })[0];"
        "if (!opt) { res.missing = true; return JSON.stringify(res); }"
        "var setter = Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value').set;"
        "setter.call(sel, opt.value);"
        "sel.dispatchEvent(new Event('input', {bubbles: true}));"
        "sel.dispatchEvent(new Event('change', {bubbles: true}));"
        "res.after = sel.value;"
        "if (save && res.before !== res.after) {"
        "  var form = sel.form;"
        "  var buttons = Array.prototype.slice.call((form || document).querySelectorAll('button, input[type=submit]'));"
        "  var press = buttons.filter(function(b){ return b.type === 'submit'; })[0]"
        "    || buttons.filter(function(b){ return /save|enregistr|speicher|guardar|salva|opslaan/i.test(b.textContent || b.value || ''); })[0];"
        "  res.save = !!press;"
        "  if (press) setTimeout(function(){ press.click(); }, 500);"
        "}"
        "return JSON.stringify(res);"
        "})('%@', %@)", code, save ? @"true" : @"false"];
}

// The market in the page's address: /ch-fr/account/... → CH.
static NSString *marketOf(NSURL *url) {
    NSString *first = url.pathComponents.count > 1 ? url.pathComponents[1] : @"";
    NSRegularExpression *market = [NSRegularExpression regularExpressionWithPattern:@"^([a-z]{2})(-[a-z]{2,3})?$" options:0 error:nil];
    NSTextCheckingResult *match = [market firstMatchInString:first options:0 range:NSMakeRange(0, first.length)];
    return match ? [first substringWithRange:[match rangeAtIndex:1]].uppercaseString : nil;
}

// One change at a time. The web view sits unseen in a 1pt corner of the window; it comes up full only to sign in.
@interface SGLocationRun : UIViewController <WKNavigationDelegate>
@end

static SGLocationRun *sg_run;

@implementation SGLocationRun {
    NSString *_code;   // empty: where Spotify places the phone
    BOOL _done, _shown;
@public
    BOOL _quiet;   // the check at launch: a banner only for a change made, no sign-in sheet
@private
    WKWebView *_web;
    int _tries;
}

- (instancetype)initWithCountry:(NSString *)code {
    if ((self = [super init])) {
        _code = code.uppercaseString ?: @"";
        self.title = @"Sign in to Spotify";
    }
    return self;
}

- (void)start {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    _web = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 390, 800) configuration:configuration];
    _web.navigationDelegate = self;
    _web.alpha = 0.01;
    _web.userInteractionEnabled = NO;
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *w in ((UIWindowScene *)scene).windows) if (w.isKeyWindow) window = w;
    [window insertSubview:_web atIndex:0];
    NSString *page = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLocationURL];
    NSURL *url = [NSURL URLWithString:[page containsString:@"spotify.com"] ? page : kProfilePage];
    SGLog(@"location: loading %@%@ unseen to set %@", url.host, url.path, _code.length ? _code : @"where Spotify places the phone");
    __weak WKWebView *web = _web;
    bringSession(_web, ^{ [web loadRequest:[NSURLRequest requestWithURL:url]]; });
    // Never more than 40 s.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(40 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_run == self && !self->_done && !self->_shown) [self endSaying:@"Spotify's account page didn't answer. Try again later."];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose primaryAction:
        [UIAction actionWithHandler:^(UIAction *action) { [self endSaying:nil]; }] menu:nil];
}

// The page wants a sign-in: it comes up, once; the session it gets is kept.
- (void)showToSignIn {
    if (_shown) return;
    _shown = YES;
    SGLog(@"location: the account page asks to sign in, shown once");
    [_web removeFromSuperview];
    _web.alpha = 1;
    _web.userInteractionEnabled = YES;
    _web.frame = self.view.bounds;
    _web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_web];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:self];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [SGTopController() presentViewController:navigation animated:YES completion:nil];
}

- (void)endSaying:(NSString *)text {
    if (text && !_quiet) banner(text);
    [_web stopLoading];
    if (_shown) [self.navigationController dismissViewControllerAnimated:YES completion:nil];
    [_web removeFromSuperview];
    if (sg_run == self) sg_run = nil;
}

- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    _tries = 0;
    [self tryNow];
}

- (void)tryNow {
    if (_done || !_web.URL) return;
    NSString *path = _web.URL.path.lowercaseString ?: @"";
    if (![_web.URL.host containsString:@"spotify.com"] || [path containsString:@"login"] || ![path containsString:@"account"]) {
        if (_quiet) {
            SGLog(@"location: launch check skipped, the account page wants a sign-in (done once from Settings > Location)");
            [self endSaying:nil];
            return;
        }
        [self showToSignIn];
        return;
    }
    if ([path containsString:@"overview"] || ![path containsString:@"profile"]) {
        // Signed in, but on another account page: straight to the profile, in the same market.
        NSString *market = _web.URL.pathComponents.count > 1 && marketOf(_web.URL) ? _web.URL.pathComponents[1] : nil;
        NSString *address = market ? [NSString stringWithFormat:@"https://www.spotify.com/%@/account/profile/", market] : kProfilePage;
        [_web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:address]]];
        return;
    }
    keepSession(_web);
    NSString *code = _code.length ? _code : (marketOf(_web.URL) ?: SGLocationDeviceCountry());
    __weak SGLocationRun *weakSelf = self;
    [_web evaluateJavaScript:script(code, YES) completionHandler:^(id result, NSError *error) {
        SGLocationRun *me = weakSelf;
        if (!me || me->_done) return;
        NSDictionary *res = [result isKindOfClass:NSString.class]
            ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if (![res[@"found"] boolValue]) {
            if (++me->_tries < 10) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [me tryNow]; });
                return;
            }
            SGLog(@"location: no country list on %@ (selects %@%@)", me->_web.URL.path, res[@"selects"] ?: @"?",
                  error ? [@", " stringByAppendingString:error.localizedDescription] : @"");
            me->_done = YES;
            [me endSaying:@"Couldn't find the country on Spotify's account page."];
            return;
        }
        me->_done = YES;
        SGLog(@"location: country %@ -> %@ (asked %@, offered %@), save %@", res[@"before"], res[@"after"] ?: @"-", code,
              res[@"offered"], res[@"save"] ?: @"not needed");
        if ([res[@"missing"] boolValue]) {
            [me endSaying:[NSString stringWithFormat:@"Spotify doesn't offer %@ from where you are now.", SGLocationName(code)]];
            return;
        }
        [NSUserDefaults.standardUserDefaults setObject:code forKey:SGKeyLocationSet];
        if ([res[@"before"] isEqual:res[@"after"]]) {
            if (me->_quiet) SGLog(@"location: launch check, the account is already %@", code);
            [me endSaying:[NSString stringWithFormat:@"Your account is already set to %@.", SGLocationName(code)]];
            return;
        }
        // The save button posts the form: a moment for it, then the session is kept again.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            keepSession(me->_web);
            [me endSaying:[res[@"save"] boolValue]
                ? [NSString stringWithFormat:@"Your account is now set to %@. Restart Spotify to play.", SGLocationName(code)]
                : @"The country is picked, but Spotify's save button wasn't found."];
        });
    }];
}
@end

// Once a launch, a moment after the app comes up: the account is put where Spotify places the phone if it
// isn't there, quietly (a banner only when it changed something).
static void checkAtLaunch(void) {
    if (!SGFlag(SGKeyLocationAuto, YES) || sg_run || SGAppInBackground()) return;
    SGLog(@"location: launch check");
    sg_run = [[SGLocationRun alloc] initWithCountry:@""];
    sg_run->_quiet = YES;
    [sg_run start];
}

void SGLocationChange(NSString *code, BOOL save) {
    (void)save;
    if (sg_run) {
        SGLog(@"location: a change is already running");
        return;
    }
    sg_run = [[SGLocationRun alloc] initWithCountry:code ?: @""];
    [sg_run start];
    banner(code.length ? [NSString stringWithFormat:@"Setting your account to %@…", SGLocationName(code)] : @"Setting your account to where you are…");
}

#pragma mark - the country list

@interface SGCountryList : SGPage <UISearchResultsUpdating>
@end

@implementation SGCountryList {
    NSArray<NSString *> *_all, *_shown;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Country";
    _all = [NSLocale.ISOCountryCodes sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [SGLocationName(a) localizedCaseInsensitiveCompare:SGLocationName(b)];
    }];
    NSString *here = SGLocationDeviceCountry();
    if (here.length) _all = [@[here] arrayByAddingObjectsFromArray:[_all filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != %@", here]]];
    _shown = _all;
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search countries";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text;
    _shown = query.length ? [_all filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *code, NSDictionary *bindings) {
        return [SGLocationName(code) localizedCaseInsensitiveContainsString:query] || [code localizedCaseInsensitiveContainsString:query];
    }]] : _all;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    return _shown.count;
}

- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = SGDequeueCell(table, @"country");
    NSString *code = _shown[path.row];
    BOOL here = [code isEqualToString:SGLocationDeviceCountry()];
    SGFillCell(cell, SGLocationName(code), here ? [NSString stringWithFormat:@"%@ · this phone's country", code] : code, nil, here ? @"location.fill" : nil);
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSString *code = _shown[path.row];
    SGLog(@"location: %@ picked in the list", code);
    SGLocationChange(code, YES);
}
@end

UIViewController *SGLocationPage(void) {
    SGModRow *automatic = SGSwitchRow(@"Match my country automatically",
        @"At each launch, and when Spotify says your location doesn't match your profile, the account is set to where you are, without leaving the app",
        SGKeyLocationAuto);
    SGModRow *now = SGActionRow(@"Set to where I am", @"The country Spotify places you in by your network", ^{ SGLocationChange(@"", YES); });
    now.symbol = @"location.fill";
    SGModRow *other = SGPageRow(@"Choose a country", ^UIViewController *{ return [[SGCountryList alloc] initWithStyle:UITableViewStyleInsetGrouped]; });
    other.symbol = @"globe";
    other.value = ^NSString *{
        NSString *set = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLocationSet];
        return set.length ? SGLocationName(set) : @"";
    };
    SGModSection *section = SGNotedSection(nil, @[automatic, now, other],
        @"The country is your account's own setting, changed on Spotify's account page in the background. The first time, that page asks you to sign in; the session is kept in the keychain, so a reinstall doesn't ask again. Spotify only offers the country it places you in.");
    return [[SGModPage alloc] initWithTitle:@"Location" intro:nil sections:@[section] footer:nil];
}

#pragma mark - Spotify's sheet

static BOOL sg_handled;

static NSString *allText(UIView *view, int depth) {
    if (depth > 14) return @"";
    NSMutableString *text = [NSMutableString string];
    if ([view isKindOfClass:UILabel.class] && ((UILabel *)view).text) [text appendFormat:@"%@ ", ((UILabel *)view).text];
    for (UIView *sub in view.subviews) [text appendString:allText(sub, depth + 1)];
    return text;
}

static BOOL saysLocationMismatch(NSString *text) {
    NSString *lower = text.lowercaseString;
    BOOL place = [lower containsString:@"emplacement"] || [lower containsString:@"location"] || [lower containsString:@"standort"]
        || [lower containsString:@"ubicación"] || [lower containsString:@"posizione"];
    BOOL profile = [lower containsString:@"profil"] || [lower containsString:@"perfil"] || [lower containsString:@"profilo"];
    return place && profile;
}

static void checkPresented(UIViewController *presented) {
    if (!presented.isViewLoaded || !presented.view.window) return;
    if (!saysLocationMismatch(allText(presented.view, 0))) return;
    SGLog(@"location: Spotify says the location doesn't match the profile (%@)", NSStringFromClass(presented.class));
    if (!SGFlag(SGKeyLocationAuto, YES) || sg_handled) return;
    sg_handled = YES;
    SGLog(@"location: setting the account to where Spotify places the phone");
    [presented dismissViewControllerAnimated:YES completion:^{ SGLocationChange(@"", YES); }];
}

%hook UIViewController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    %orig;
    __weak UIViewController *weakController = controller;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *shown = weakController;
        if (shown && ![shown isKindOfClass:UIAlertController.class]) checkPresented(shown);
    });
}
%end

// The address Spotify's own "Change location" button opens is kept: it is the page to set the country on.
%hook UIApplication
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    NSString *text = url.absoluteString;
    if ([url.host containsString:@"spotify.com"] && [text.lowercaseString containsString:@"account"]) {
        [NSUserDefaults.standardUserDefaults setObject:text forKey:SGKeyLocationURL];
        SGLog(@"location: Spotify opened %@%@", url.host, url.path);
    }
    %orig;
}
%end

%ctor {
    __block id watcher = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil
                                                                          queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:watcher];
        watcher = nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ checkAtLaunch(); });
    }];
    SGDebug(@"module Shared/Location/Location.x on");
    %init;
}
