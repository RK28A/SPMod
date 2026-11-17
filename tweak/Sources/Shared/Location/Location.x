// Changing the account's country from the app. The account page (spotify.com/account/profile) opens in a web
// view of the mod's; once it has loaded (after signing in, the first time), a script finds the country list
// (the <select> whose options are country codes), picks the country and presses the page's save button. The
// page stays on screen, so a change it could not make is finished by hand. Every step goes to the log.
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
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

static NSString *script(NSString *code, BOOL save) {
    return [NSString stringWithFormat:@
        "(function(code, save){"
        "var res = {url: location.href};"
        "var selects = Array.prototype.slice.call(document.querySelectorAll('select'));"
        "res.selects = selects.length;"
        "var sel = selects.filter(function(s){ return s.options.length > 50 && Array.prototype.some.call(s.options, function(o){ return (o.value||'').toUpperCase() === code; }); })[0];"
        "if (!sel) { res.found = false; return JSON.stringify(res); }"
        "res.found = true; res.before = sel.value;"
        "var opt = Array.prototype.filter.call(sel.options, function(o){ return (o.value||'').toUpperCase() === code; })[0];"
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

@interface SGLocationWeb : UIViewController <WKNavigationDelegate>
- (instancetype)initWithCountry:(NSString *)code save:(BOOL)save;
@end

@implementation SGLocationWeb {
    NSString *_code;
    BOOL _save, _done;
    WKWebView *_web;
    UILabel *_status;
    int _tries;
}

- (instancetype)initWithCountry:(NSString *)code save:(BOOL)save {
    if ((self = [super init])) {
        _code = code.uppercaseString;
        _save = save;
        self.title = @"Location";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = SGPageBackground();
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _web = [[WKWebView alloc] initWithFrame:CGRectZero configuration:[WKWebViewConfiguration new]];
    _web.navigationDelegate = self;
    _web.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_web];
    _status = [UILabel new];
    _status.font = SGSubtitleFont();
    _status.textColor = UIColor.whiteColor;
    _status.numberOfLines = 0;
    _status.textAlignment = NSTextAlignmentCenter;
    _status.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_status];
    [NSLayoutConstraint activateConstraints:@[
        [_web.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_web.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_web.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_web.bottomAnchor constraintEqualToAnchor:_status.topAnchor],
        [_status.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_status.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_status.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_status.heightAnchor constraintGreaterThanOrEqualToConstant:84],
    ]];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose primaryAction:
        [UIAction actionWithHandler:^(UIAction *action) { [self dismissViewControllerAnimated:YES completion:nil]; }] menu:nil];
    [self say:[NSString stringWithFormat:@"Opening your account to set %@…", SGLocationName(_code)]];
    NSString *page = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLocationURL];
    NSURL *url = [NSURL URLWithString:[page containsString:@"spotify.com"] ? page : kProfilePage];
    SGLog(@"location: opening %@ to set %@", url.host, _code);
    [_web loadRequest:[NSURLRequest requestWithURL:url]];
}

- (void)say:(NSString *)text {
    _status.text = [NSString stringWithFormat:@"%@\n", text];
}

- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)navigation {
    _tries = 0;
    [self tryNow];
}

// The page draws its form after it loads: a second at a time, ten times.
- (void)tryNow {
    if (_done || !_web.URL) return;
    NSString *path = _web.URL.path.lowercaseString ?: @"";
    if (![_web.URL.host containsString:@"spotify.com"] || ![path containsString:@"account"]) {
        [self say:@"Sign in to your Spotify account; the country is set once your profile shows."];
        return;
    }
    __weak SGLocationWeb *weakSelf = self;
    [_web evaluateJavaScript:script(_code, _save) completionHandler:^(id result, NSError *error) {
        SGLocationWeb *me = weakSelf;
        if (!me) return;
        NSDictionary *res = [result isKindOfClass:NSString.class]
            ? [NSJSONSerialization JSONObjectWithData:[result dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
        if (![res[@"found"] boolValue]) {
            if (++me->_tries < 10) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [me tryNow]; });
                return;
            }
            SGLog(@"location: no country list on %@ (%@ select(s)%@)", me->_web.URL.path, res[@"selects"] ?: @"?",
                  error ? [@", " stringByAppendingString:error.localizedDescription] : @"");
            [me say:[NSString stringWithFormat:@"Couldn't find the country on this page. Pick %@ yourself and save.", SGLocationName(me->_code)]];
            return;
        }
        me->_done = YES;
        BOOL changed = ![res[@"before"] isEqual:res[@"after"]];
        SGLog(@"location: country %@ -> %@, save %@", res[@"before"], res[@"after"], res[@"save"] ?: @"not needed");
        [NSUserDefaults.standardUserDefaults setObject:me->_code forKey:SGKeyLocationSet];
        if (!changed) [me say:[NSString stringWithFormat:@"Your profile is already set to %@.", SGLocationName(me->_code)]];
        else if (!me->_save) [me say:[NSString stringWithFormat:@"%@ is picked: check the page and save.", SGLocationName(me->_code)]];
        else if ([res[@"save"] boolValue]) [me say:[NSString stringWithFormat:@"Saved: your profile is now %@. Restart Spotify to play again.", SGLocationName(me->_code)]];
        else [me say:[NSString stringWithFormat:@"%@ is picked, but no save button was found: save it on the page.", SGLocationName(me->_code)]];
    }];
}
@end

void SGLocationChange(NSString *code, BOOL save) {
    if (!code.length) return;
    UIViewController *top = SGTopController();
    if (!top) return;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[[SGLocationWeb alloc] initWithCountry:code save:save]];
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [top presentViewController:navigation animated:YES completion:nil];
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
    NSString *here = SGLocationDeviceCountry();
    SGModRow *automatic = SGSwitchRow(@"Match my country automatically",
        [NSString stringWithFormat:@"When Spotify says your location doesn't match your profile, the profile is set to this phone's country (%@)", SGLocationName(here)],
        SGKeyLocationAuto);
    SGModRow *now = SGActionRow(@"Set to this phone's country", SGLocationName(here), ^{ SGLocationChange(SGLocationDeviceCountry(), YES); });
    now.symbol = @"location.fill";
    SGModRow *other = SGPageRow(@"Choose a country", ^UIViewController *{ return [[SGCountryList alloc] initWithStyle:UITableViewStyleInsetGrouped]; });
    other.symbol = @"globe";
    other.value = ^NSString *{
        NSString *set = [NSUserDefaults.standardUserDefaults stringForKey:SGKeyLocationSet];
        return set.length ? SGLocationName(set) : @"";
    };
    SGModSection *section = SGNotedSection(nil, @[automatic, now, other],
        @"The country is your account's own setting: it is changed on your Spotify account page, signed in the first time. Spotify may limit how often it can change.");
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
    NSString *here = SGLocationDeviceCountry();
    SGLog(@"location: setting the profile to this phone's country, %@", here);
    [presented dismissViewControllerAnimated:YES completion:^{ SGLocationChange(here, YES); }];
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
    SGDebug(@"module Shared/Location/Location.x on");
    %init;
}
