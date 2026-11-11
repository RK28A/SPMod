#import "SGPresets.h"
#import "Core/SGCore.h"
#import "Core/SGPrefs.h"
#import "Settings/SGPageStyle.h"

static NSString *const kPresetsKey = @"spotifyglass.presets";
static NSString *const kAccentKey = @"spotifyglass.accent";
static NSString *const kAmoledKey = @"spotifyglass.amoled";
static NSString *const kRedesignAccentKey = @"spotifyglass.redesign.accent";

static NSArray<NSDictionary *> *loadPresets(void) {
    return [NSUserDefaults.standardUserDefaults arrayForKey:kPresetsKey] ?: @[];
}

static void storePresets(NSArray<NSDictionary *> *presets) {
    [NSUserDefaults.standardUserDefaults setObject:presets forKey:kPresetsKey];
}

static void saveCurrent(NSString *name) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *preset = [NSMutableDictionary dictionary];
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    preset[@"id"] = NSUUID.UUID.UUIDString;
    preset[@"name"] = trimmed.length ? trimmed : [NSString stringWithFormat:@"Preset %lu", (unsigned long)(loadPresets().count + 1)];
    if ([defaults objectForKey:kAccentKey]) preset[@"accent"] = @([defaults integerForKey:kAccentKey]);
    preset[@"amoled"] = @([defaults boolForKey:kAmoledKey]);
    if ([defaults objectForKey:kRedesignAccentKey]) preset[@"redesignAccent"] = @([defaults integerForKey:kRedesignAccentKey]);
    storePresets([loadPresets() arrayByAddingObject:preset]);
}

static void applyPreset(NSDictionary *preset) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (preset[@"accent"]) SGSetInt(kAccentKey, [preset[@"accent"] integerValue]);
    else [defaults removeObjectForKey:kAccentKey];
    [defaults setBool:[preset[@"amoled"] boolValue] forKey:kAmoledKey];
    if (preset[@"redesignAccent"]) SGSetInt(kRedesignAccentKey, [preset[@"redesignAccent"] integerValue]);
}

static void deletePreset(NSString *presetId) {
    NSMutableArray *kept = [NSMutableArray array];
    for (NSDictionary *preset in loadPresets()) {
        if (![preset[@"id"] isEqual:presetId]) [kept addObject:preset];
    }
    storePresets(kept);
}

static void presentNamePrompt(void) {
    UIViewController *top = SGTopController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Save preset"
        message:@"Save the current theme under a name." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"Preset name";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        saveCurrent(alert.textFields.firstObject.text ?: @"");
    }]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void presentDeleteMenu(void) {
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Delete a preset" message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *preset in loadPresets()) {
        [sheet addAction:[UIAlertAction actionWithTitle:preset[@"name"] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            deletePreset(preset[@"id"]);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

static void confirmApplied(void) {
    UIViewController *top = SGTopController();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Preset applied"
        message:@"Restart Spotify to apply it fully." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [top presentViewController:alert animated:YES completion:nil];
}

static void openManager(void) {
    UIViewController *top = SGTopController();
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Theme presets" message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    [sheet addAction:[UIAlertAction actionWithTitle:@"Save current theme…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        presentNamePrompt();
    }]];

    for (NSDictionary *preset in loadPresets()) {
        [sheet addAction:[UIAlertAction actionWithTitle:preset[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            applyPreset(preset);
            confirmApplied();
        }]];
    }

    if (loadPresets().count) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Delete a preset…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            presentDeleteMenu();
        }]];
    }

    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = top.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 0, 0);
    sheet.popoverPresentationController.permittedArrowDirections = 0;
    [top presentViewController:sheet animated:YES completion:nil];
}

SGModRow *SGPresetsRow(void) {
    return SGWithSymbol(
        SGStatActionRow(@"Theme presets",
                        @"Save the current theme and switch between saved ones",
                        ^NSString *{
                            NSUInteger count = loadPresets().count;
                            return count ? [NSString stringWithFormat:@"%lu saved", (unsigned long)count] : @"None yet";
                        },
                        ^{ openManager(); }),
        @"square.stack.3d.up");
}
