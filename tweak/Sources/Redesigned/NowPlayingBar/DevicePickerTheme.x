// The device button of the now playing bar and the device picker it opens, in the redesign's colours.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"

// Spotify draws the button green for the moment it is pressed, before the picker opens: the accent is put
// back on it as the press starts and ends.
static void retintButton(UIView *owner) {
    SGRAccentRetint(owner);
    // The disc that lights up behind the glyph while it is pressed.
    UIColor *accent = SGRAccentColor();
    for (UIView *sub in owner.subviews) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        if (!accent || [sub isKindOfClass:UIControl.class] || ![sub.backgroundColor getRed:&r green:&g blue:&b alpha:&a]) continue;
        if (a > 0.02 && g > 0.4 && g > r * 1.4 && g > b * 1.2) sub.backgroundColor = [accent colorWithAlphaComponent:a];
    }
}

%hook UIButton
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    UIView *owner = ((UIView *)self).superview;
    static Class connect;
    if (connect ? object_getClass(owner) != connect : ![NSStringFromClass(owner.class) containsString:@"ConnectButtonView"]) return;
    if (!connect) connect = object_getClass(owner);
    retintButton(owner);
    dispatch_async(dispatch_get_main_queue(), ^{ retintButton(owner); });
}
%end

// The picker (Connect_DevicePickerUIImpl.DevicePickerViewController, the recorded sheet) takes the accent's
// light or the moving background behind its list. What it draws is SwiftUI's: the green of the song's name,
// of the device's glyph and of Bluetooth is no view's colour to set, so the hosting view is drawn through a
// filter that turns Spotify's green round to the accent's hue (or drains it for a grey accent). Whites and
// greys have no hue and stay as they are; the light behind is the page's, outside the filter.
static const CGFloat kGreenHue = 141.0 / 360.0;

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

static void turnGreen(UIView *host) {
    static char kHueKey;
    UIColor *accent = SGRAccentColor();
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 0;
    if (!accent || ![accent getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return;
    NSNumber *now = @(saturation < 0.12 ? -1 : hue);
    if ([objc_getAssociatedObject(host, &kHueKey) isEqual:now]) return;
    objc_setAssociatedObject(host, &kHueKey, now, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class maker = NSClassFromString(@"CAFilter");
    if (![maker respondsToSelector:@selector(filterWithType:)]) return;
    id filter = nil;
    if (saturation < 0.12) {
        filter = [maker filterWithType:@"colorSaturate"];
        [filter setValue:@0 forKey:@"inputAmount"];
    } else {
        filter = [maker filterWithType:@"colorHueRotate"];
        [filter setValue:@((hue - kGreenHue) * 2 * M_PI) forKey:@"inputAngle"];
    }
    host.layer.filters = filter ? @[filter] : nil;
}

%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (!page) return;
    SGRAccentWashPlace(page);
    for (UIView *sub in page.subviews) {
        if ([NSStringFromClass(sub.class) containsString:@"UIHostingView"]) turnGreen(sub);
    }
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
