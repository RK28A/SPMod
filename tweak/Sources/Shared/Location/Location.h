// The account's country. Spotify stops playback with "Your current location doesn't match your profile" when
// the profile's country is not where the phone is; the profile is the account's own setting on spotify.com,
// so the mod changes it there, in a web view on the account page, as one would by hand.
#import <UIKit/UIKit.h>

// On unless switched off: when Spotify shows that sheet, the profile is set to this phone's country.
#define SGKeyLocationAuto @"spotifyglass.location.auto"
// The account page Spotify's own "Change location" button opened, kept from the last time it was tapped.
#define SGKeyLocationURL @"spotifyglass.location.url"
// The country last set from the mod (ISO code).
#define SGKeyLocationSet @"spotifyglass.location.set"

// This phone's country (its region), as an ISO code.
NSString *SGLocationDeviceCountry(void);
// A country's name in the phone's language.
NSString *SGLocationName(NSString *code);
// Opens the account page and sets the profile's country to `code`, saving it when `save` is YES.
void SGLocationChange(NSString *code, BOOL save);
UIViewController *SGLocationPage(void);
