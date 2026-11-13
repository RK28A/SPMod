#import <UIKit/UIKit.h>
#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "WebJam.h"

// The code to scan and the address to type, nothing else: the settings page stays where it is.
@interface SGWebJamSheet : UIViewController
@end

@implementation SGWebJamSheet {
    UIImageView *_code;
    UILabel *_title, *_address, *_note;
    UIButton *_copy;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    _title = [UILabel new];
    _title.text = @"Web Jam";
    _title.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    _title.textColor = UIColor.whiteColor;
    _code = [UIImageView new];
    _code.contentMode = UIViewContentModeScaleAspectFit;
    _code.layer.magnificationFilter = kCAFilterNearest;
    _code.layer.cornerRadius = 18;
    _code.layer.cornerCurve = kCACornerCurveContinuous;
    _code.clipsToBounds = YES;
    _address = [UILabel new];
    _address.font = [UIFont monospacedSystemFontOfSize:17 weight:UIFontWeightSemibold];
    _address.textColor = UIColor.whiteColor;
    _address.textAlignment = NSTextAlignmentCenter;
    _address.adjustsFontSizeToFitWidth = YES;
    _note = [UILabel new];
    _note.font = [UIFont systemFontOfSize:14];
    _note.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _note.textAlignment = NSTextAlignmentCenter;
    _note.numberOfLines = 0;
    _copy = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *look = [UIButtonConfiguration filledButtonConfiguration];
    look.title = @"Copy the address";
    look.image = [UIImage systemImageNamed:@"doc.on.doc"];
    look.imagePadding = 8;
    look.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    _copy.configuration = look;
    [_copy addTarget:self action:@selector(copyAddress) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *view in @[_title, _code, _address, _note, _copy]) [self.view addSubview:view];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:SGWebJamDidChangeNotification object:nil];
    [self refresh];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refresh {
    NSString *url = SGWebJamJoinURL();
    _code.image = url ? SGWebJamQRCode(url) : nil;
    _code.alpha = url ? 1 : 0.15;
    _address.text = url ?: SGWebJamStatus();
    _note.text = url ? @"Guests on this Wi-Fi scan the code or open the address to add songs to the queue."
                     : @"Web Jam needs this iPhone on Wi-Fi, with Web Jam on in SPMod settings.";
    _copy.enabled = url != nil;
    _copy.tintColor = self.view.tintColor;
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.view.bounds.size.width, top = 28, side = MIN(260, width - 96);
    _title.frame = CGRectMake(24, top, width - 48, 32);
    _code.frame = CGRectMake((width - side) / 2, top + 52, side, side);
    _address.frame = CGRectMake(24, CGRectGetMaxY(_code.frame) + 20, width - 48, 24);
    CGFloat noteHeight = [_note sizeThatFits:CGSizeMake(width - 64, 200)].height;
    _note.frame = CGRectMake(32, CGRectGetMaxY(_address.frame) + 10, width - 64, noteHeight);
    _copy.frame = CGRectMake(40, CGRectGetMaxY(_note.frame) + 20, width - 80, 50);
}

- (void)copyAddress {
    NSString *url = SGWebJamJoinURL();
    if (!url) return;
    UIPasteboard.generalPasteboard.string = url;
    [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
    SGLog(@"web jam: address copied from the sheet");
}

@end

void SGWebJamShowSheet(void) {
    UIViewController *top = SGTopController();
    if (!top || [top isKindOfClass:SGWebJamSheet.class]) return;
    SGWebJamSheet *sheet = [SGWebJamSheet new];
    sheet.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 16.0, *)) {
        sheet.sheetPresentationController.detents = @[[UISheetPresentationControllerDetent customDetentWithIdentifier:@"jam" resolver:^CGFloat(id context) { return 520; }],
                                                      UISheetPresentationControllerDetent.largeDetent];
    }
    sheet.sheetPresentationController.prefersGrabberVisible = YES;
    sheet.sheetPresentationController.preferredCornerRadius = 32;
    SGLog(@"web jam: sheet opened (%@)", SGWebJamJoinURL() ?: SGWebJamStatus());
    [top presentViewController:sheet animated:YES completion:nil];
}
