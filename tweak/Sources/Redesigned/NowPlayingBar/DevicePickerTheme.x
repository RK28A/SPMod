// The device button of the now playing bar and the device picker it opens, in the redesign's colours.
#import "Redesigned/Kit/SGRKit.h"

// Spotify draws the button green for the moment it is pressed, before the picker opens: the accent is put
// back on it as the press starts and ends.
%hook UIButton
- (void)setHighlighted:(BOOL)highlighted {
    %orig;
    UIView *owner = ((UIView *)self).superview;
    if (![NSStringFromClass(owner.class) containsString:@"ConnectButtonView"]) return;
    SGRAccentRetint(owner);
    dispatch_async(dispatch_get_main_queue(), ^{ SGRAccentRetint(owner); });
}
%end

// The picker (Connect_DevicePickerUIImpl.DevicePickerViewController, the recorded sheet) takes the accent's
// light or the moving background behind its list.
%hook _TtC26Connect_DevicePickerUIImpl26DevicePickerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIView *page = ((UIViewController *)self).viewIfLoaded;
    if (page) SGRAccentWashPlace(page);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
}
