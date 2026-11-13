#import <Security/Security.h>
#import "Core/SGCore.h"
#import "StatsVault.h"

static NSString *const kService = @"pw.spoti.spmod.settings", *const kAccount = @"listening";
static const NSUInteger kLargest = 6 * 1024 * 1024;   // packed; years of plays come to far less
static const NSTimeInterval kSaveEvery = 600;

static NSDictionary *query(void) {
    return @{(id)kSecClass: (id)kSecClassGenericPassword, (id)kSecAttrService: kService, (id)kSecAttrAccount: kAccount};
}

void SGStatsVaultRestore(NSString *path) {
    NSFileManager *files = NSFileManager.defaultManager;
    if ([[files attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue] > 0) return;
    NSMutableDictionary *ask = [query() mutableCopy];
    ask[(id)kSecReturnData] = @YES;
    ask[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    CFTypeRef found = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)ask, &found) != errSecSuccess || !found) return;
    NSData *packed = (__bridge_transfer NSData *)found;
    NSData *log = [packed decompressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:nil];
    if (!log.length) return;
    [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    BOOL written = [log writeToFile:path atomically:YES];
    SGLog(@"listening stats: %lu bytes of plays from an earlier install %@", (unsigned long)log.length, written ? @"put back" : @"could not be written");
}

void SGStatsVaultSave(NSString *path, BOOL now) {
    static NSDate *kept;        // the file's date when it was last saved
    static CFAbsoluteTime last;
    NSDate *changed = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil][NSFileModificationDate];
    if (!changed || [changed isEqualToDate:kept]) return;
    if (!now && CFAbsoluteTimeGetCurrent() - last < kSaveEvery) return;
    last = CFAbsoluteTimeGetCurrent();
    NSData *packed = [[NSData dataWithContentsOfFile:path] compressedDataUsingAlgorithm:NSDataCompressionAlgorithmZlib error:nil];
    if (!packed.length || packed.length > kLargest) {
        if (packed.length) SGLog(@"listening stats: the log packs to %lu bytes, too much for the keychain, not saved", (unsigned long)packed.length);
        return;
    }
    NSDictionary *fresh = @{(id)kSecValueData: packed, (id)kSecAttrAccessible: (id)kSecAttrAccessibleAfterFirstUnlock};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query(), (__bridge CFDictionaryRef)fresh);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [query() mutableCopy];
        [item addEntriesFromDictionary:fresh];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    if (status == errSecSuccess) kept = changed;
    else SGLog(@"listening stats: not saved to the keychain (%d)", (int)status);
}

void SGStatsVaultForget(void) {
    SecItemDelete((__bridge CFDictionaryRef)query());
}
