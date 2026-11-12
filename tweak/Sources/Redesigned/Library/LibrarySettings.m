#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Library.h"

UIViewController *SGRLibrarySettingsPage(void) {
    SGModRow *chips = SGOptionRow(@"Hide filter chips", @"Playlists, Podcasts, Albums and Artists under the title", SGRKeyLibraryHideChips);
    return [[SGModPage alloc] initWithTitle:@"Library"
                                      intro:nil
                                   sections:@[SGSection(nil, @[chips, SGSwitchRow(@"Liquid Glass rows", @"Each playlist, artist and button on a card of glass", SGRKeyLibraryGlass)])]
                                     footer:@"Changes apply after restarting Spotify."];
}
