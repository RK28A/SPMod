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
// light or the moving background behind its list. What it draws is SwiftUI's, in the colour Spotify was
// handed when it first made its green (the accent of that moment, SGRAccentHanded): no view's colour to
// set. The hosting view is drawn through a filter that turns that hue round to the accent's of now (or
// drains it for a grey accent). Whites and greys have no hue and stay as they are; the light behind is the
// page's, outside the filter.
@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

static void turnGreen(UIView *host) {
    static char kTurnKey;
    UIColor *accent = SGRAccentColor(), *handed = SGRAccentHanded();
    CGFloat hue = 0, saturation = 0, was = 0, wasSaturation = 0, brightness = 0, alpha = 0;
    if (!accent || !handed || ![accent getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]
        || ![handed getHue:&was saturation:&wasSaturation brightness:&brightness alpha:&alpha]) return;
    // A grey has no hue to turn from; one to turn to is reached by draining the colour.
    NSNumber *turn = wasSaturation < 0.12 ? @0 : saturation < 0.12 ? @(-100) : @(hue - was);
    if ([objc_getAssociatedObject(host, &kTurnKey) isEqual:turn]) return;
    objc_setAssociatedObject(host, &kTurnKey, turn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    Class maker = NSClassFromString(@"CAFilter");
    id filter = nil;
    if ([maker respondsToSelector:@selector(filterWithType:)] && fabs(turn.doubleValue) > 0.004) {
        if (turn.doubleValue < -10) {
            filter = [maker filterWithType:@"colorSaturate"];
            [filter setValue:@0 forKey:@"inputAmount"];
        } else {
            filter = [maker filterWithType:@"colorHueRotate"];
            [filter setValue:@(turn.doubleValue * 2 * M_PI) forKey:@"inputAngle"];
        }
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
