#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "SGBackdrop.h"
#import "SGModPage.h"
#import "SGPageStyle.h"

// The Gradient background's own page: its three colours (each the theme's, a turn of it, or one picked), its
// shape, its angle, how it moves and how far it fades to black. A change reaches the background at once.

static void changed(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:SGBackdropDidChangeNotification object:nil];
}

static UIColor *fromRGB(NSInteger rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static NSInteger rgbOf(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return -1;
    return ((NSInteger)lround(MIN(1, MAX(0, r)) * 255) << 16) | ((NSInteger)lround(MIN(1, MAX(0, g)) * 255) << 8) | (NSInteger)lround(MIN(1, MAX(0, b)) * 255);
}

static NSString *nameOf(NSInteger rgb) {
    if (rgb == -1) return @"Theme";
    if (rgb == -2) return @"Theme, turned";
    if (rgb < 0) return @"None";
    return [NSString stringWithFormat:@"#%06lX", (long)rgb];
}

@interface SGGradientPicker : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *key;
@end

@implementation SGGradientPicker
- (void)colorPickerViewController:(UIColorPickerViewController *)picker didSelectColor:(UIColor *)color continuously:(BOOL)continuously {
    if (continuously) return;
    NSInteger rgb = rgbOf(color);
    if (rgb < 0) return;
    SGSetInt(self.key, rgb);
    SGDebug(@"background: gradient %@ set to %@", self.key.pathExtension, nameOf(rgb));
    changed();
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)picker {
    objc_setAssociatedObject(picker, (__bridge const void *)self, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NSNotificationCenter.defaultCenter postNotificationName:SGBackdropDidChangeNotification object:nil];
}
@end

static void pick(NSString *key, NSInteger fallback) {
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    NSInteger now = SGInt(key, fallback);
    if (now >= 0) picker.selectedColor = fromRGB(now);
    picker.supportsAlpha = NO;
    picker.title = @"Gradient colour";
    SGGradientPicker *delegate = [SGGradientPicker new];
    delegate.key = key;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, (__bridge const void *)delegate, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [SGTopController() presentViewController:picker animated:YES completion:nil];
}

static SGModRow *colourRow(NSString *title, NSString *key, NSInteger fallback, BOOL optional) {
    return SGStatActionRow(title, nil, ^NSString *{ return nameOf(SGInt(key, fallback)); }, ^{
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Pick a colour" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { pick(key, fallback); }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"The theme's colour" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            SGSetInt(key, -1);
            changed();
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"The theme's, turned" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            SGSetInt(key, -2);
            changed();
        }]];
        if (optional) {
            [sheet addAction:[UIAlertAction actionWithTitle:@"None" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
                SGSetInt(key, -3);
                changed();
            }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *top = SGTopController();
        sheet.popoverPresentationController.sourceView = top.view;
        [top presentViewController:sheet animated:YES completion:nil];
    });
}

UIViewController *SGGradientSettingsPage(void) {
    SGModRow *first = SGWithSymbol(colourRow(@"First colour", SGKeyGradientColor1, -1, NO), @"circle.fill");
    SGModRow *second = SGWithSymbol(colourRow(@"Second colour", SGKeyGradientColor2, -2, NO), @"circle.lefthalf.filled");
    SGModRow *third = SGWithSymbol(colourRow(@"Third colour", SGKeyGradientColor3, -3, YES), @"circle");
    for (SGModRow *row in @[first, second, third]) row.refreshOn = SGBackdropDidChangeNotification;

    SGModRow *kind = SGWithSymbol(SGChoiceRow(@"Shape", nil, SGKeyGradientKind, @[@"Linear", @"Radial", @"Conic"], 0), @"square.on.circle");
    kind.choiceNotes = @[@"From one side to the other, at the angle below.", @"From the middle out.", @"Round the middle, starting at the angle below."];
    SGModRow *motion = SGWithSymbol(SGChoiceRow(@"Motion", nil, SGKeyGradientMotion, @[@"Still", @"Drift", @"Turn", @"Breathe"], 1), @"wind");
    motion.choiceNotes = @[@"It does not move: the lightest on the phone.", @"It slides and sways slowly.", @"It turns round the middle.", @"It swells and fades."];
    for (SGModRow *row in @[kind, motion]) row.chosen = ^(NSInteger index) { changed(); };

    NSString *(^degrees)(double) = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f°", value]; };
    NSString *(^percent)(double) = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100]; };
    SGModRow *angle = SGSliderRow(@"Angle", @"Which way the colours run", 0, 360, 5,
        ^double { return SGInt(SGKeyGradientAngle, 160); },
        ^(double value) { SGSetInt(SGKeyGradientAngle, (NSInteger)lround(value)); changed(); }, degrees);
    SGModRow *depth = SGSliderRow(@"Fade to black", @"How much of the bottom goes dark", 0, 1, 0.05,
        ^double {
            id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyGradientDepth];
            return stored ? [stored doubleValue] : 0.5;
        },
        ^(double value) { [NSUserDefaults.standardUserDefaults setDouble:value forKey:SGKeyGradientDepth]; changed(); }, percent);

    SGModRow *reset = SGActionRow(@"Back to the gradient as it came", nil, ^{
        for (NSString *key in @[SGKeyGradientColor1, SGKeyGradientColor2, SGKeyGradientColor3, SGKeyGradientKind, SGKeyGradientAngle,
                                SGKeyGradientMotion, SGKeyGradientDepth]) [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        changed();
        [SGTopController().navigationController popViewControllerAnimated:YES];
    });

    return [[SGModPage alloc] initWithTitle:@"Gradient" intro:nil sections:@[
        SGNotedSection(@"Colours", @[first, second, third], @"Theme follows the background's colour (the song's or the accent). Turned is the same a little round the colour wheel and darker."),
        SGSection(@"Shape", @[kind, angle, depth]),
        SGNotedSection(@"Motion", @[motion], @"Speed, brightness and how it answers the music are under Customise this style."),
        SGSection(nil, @[SGWithSymbol(reset, @"arrow.counterclockwise")]),
    ] footer:nil];
}
