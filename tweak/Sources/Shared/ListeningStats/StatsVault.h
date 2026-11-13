#import <Foundation/Foundation.h>

// The listening log kept outside the app, so a reinstall brings the stats back: the log file, packed, as an
// item of the keychain beside the settings' (App/About/Vault.x), which iOS keeps when the app is deleted.
// The keychain is the signing team's, so an install signed with another certificate starts an empty log.
// Main thread.

// Before the log is first opened: an install with no log takes the one the keychain holds.
void SGStatsVaultRestore(NSString *path);
// After a play is written and as the app leaves the foreground: the file is kept again when it has changed,
// at most once every ten minutes unless `now`.
void SGStatsVaultSave(NSString *path, BOOL now);
// The stats were erased by hand: the kept copy goes too, or the next launch would bring them back.
void SGStatsVaultForget(void);
