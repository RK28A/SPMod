// The mod's settings kept outside the app, so they outlive it: every key the mod stores (themes, presets,
// switches, the tour's answers) as one property list in the keychain, written again ten seconds after any
// of them changes and as the app leaves the foreground. iOS keeps a keychain item when an app is deleted, and
// an update installed over the app keeps the app's own store anyway, so nothing is asked then.
//
// A launch that finds its own store without the mark this file leaves, and a saved list in the keychain, is
// a fresh install over an earlier one: it asks once. Keep puts every saved key back and restarts. Reset to
// default, in red, asks a second time, saying the saved themes, presets and settings are deleted for good,
// and only then deletes the list and restarts. Until one is chosen nothing is written over the saved list.
//
// The keychain is the signing team's: an install signed with another certificate cannot read the list an
// earlier one left, and starts afresh without asking.
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"

static NSString *const kService = @"pw.spoti.spmod.settings", *const kAccount = @"all";
static NSString *const kMark = @"spotifyglass.vault.mark";
static const NSTimeInterval kSaveAfter = 10;

static BOOL sg_saving, sg_queued;
static NSData *sg_lastSaved;

// What is the device's own and not a setting: counters, what an update check last saw, the signing check,
// and what is only remembered about the account or the song playing, which changes with every track.
static BOOL isKept(NSString *key) {
    if (![key hasPrefix:@"spotifyglass."] || [key isEqualToString:kMark]) return NO;
    for (NSString *local in @[@"spotifyglass.adblock.counts", @"spotifyglass.privacy.counts", @"spotifyglass.update.",
                              @"spotifyglass.signing.", @"spotifyglass.animatedbg.songColor", @"spotifyglass.fusion.names",
                              @"spotifyglass.fusion.recent", @"spotifyglass.fusion.me", @"spotifyglass.spclient."]) {
        if ([key hasPrefix:local]) return NO;
    }
    return YES;
}

static NSDictionary *query(void) {
    return @{(id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: kService, (id)kSecAttrAccount: kAccount};
}

static NSDictionary *savedSettings(void) {
    NSMutableDictionary *ask = [query() mutableCopy];
    ask[(id)kSecReturnData] = @YES;
    ask[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef found = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)ask, &found) != errSecSuccess || !found) return nil;
    NSData *data = (__bridge_transfer NSData *)found;
    id list = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
    return [list isKindOfClass:NSDictionary.class] && [list count] ? list : nil;
}

static void deleteSaved(void) {
    SecItemDelete((__bridge CFDictionaryRef)query());
}

static void save(void) {
    sg_queued = NO;
    if (!sg_saving) return;
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults persistentDomainForName:NSBundle.mainBundle.bundleIdentifier] ?: @{};
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *key in stored) {
        if (isKept(key)) settings[key] = stored[key];
    }
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (!data || [data isEqualToData:sg_lastSaved]) return;
    NSDictionary *fresh = @{(id)kSecValueData: data, (id)kSecAttrAccessible: (id)kSecAttrAccessibleAfterFirstUnlock};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query(), (__bridge CFDictionaryRef)fresh);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [query() mutableCopy];
        [item addEntriesFromDictionary:fresh];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    if (status == errSecSuccess) sg_lastSaved = data;
    else SGLog(@"settings vault: not saved (%d)", (int)status);
}

// Spotify writes to the same store all the time, in the background too: nothing is queued there, where
// leaving the foreground has already saved, so the app is not woken every few seconds to compare lists.
static void saveSoon(void) {
    if (!sg_saving || sg_queued || UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return;
    sg_queued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kSaveAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ save(); });
}

static void begin(void) {
    SGSetEnabled(kMark, YES);
    sg_saving = YES;
    saveSoon();
}

static void present(UIAlertController *alert, int triesLeft) {
    UIViewController *top = SGTopController();
    if (top.view.window && !top.isBeingPresented && !top.isBeingDismissed) {
        [top presentViewController:alert animated:YES completion:nil];
    } else if (triesLeft > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ present(alert, triesLeft - 1); });
    }
}

static void ask(NSDictionary *saved);

static void askAgain(NSDictionary *saved) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Are you sure you want to reset the configuration to default?"
        message:@"Your saved themes, presets and settings will be permanently deleted and cannot be recovered."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete and reset to default" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        deleteSaved();
        SGLog(@"settings vault: the saved configuration was deleted, starting from default");
        SGSetEnabled(kMark, YES);
        SGRestartSpotify();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Go back" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { ask(saved); }]];
    present(alert, 5);
}

static void ask(NSDictionary *saved) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Saved configuration found"
        message:[NSString stringWithFormat:@"SPMod kept your configuration from an earlier install: %lu settings, with your themes and presets. Keep it, or start again from default?", (unsigned long)saved.count]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Keep my configuration" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        for (NSString *key in saved) {
            if (isKept(key)) [store setObject:saved[key] forKey:key];
        }
        SGLog(@"settings vault: %lu saved settings put back", (unsigned long)saved.count);
        SGSetEnabled(kMark, YES);
        SGRestartSpotify();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset to default" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { askAgain(saved); }]];
    present(alert, 20);
}

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { saveSoon(); }];
        [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { save(); }];
        if (SGFlag(kMark, NO)) {
            sg_saving = YES;
            saveSoon();
            return;
        }
        NSDictionary *saved = savedSettings();
        if (!saved) {
            begin();
            return;
        }
        SGLog(@"settings vault: a fresh install with %lu saved settings, asking", (unsigned long)saved.count);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ask(saved); });
    });
}
