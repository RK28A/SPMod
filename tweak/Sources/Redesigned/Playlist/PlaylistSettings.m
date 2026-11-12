#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGRPlaylistSettingsPage(void) {
    SGModRow *fullCover = SGSwitchRow(@"Full screen cover", nil, SGRKeyPlaylistFullCover);
    fullCover.info = @"Spreads the playlist's cover edge to edge behind the title, with a fade at the foot and a blur as you scroll. Off, the cover stays a card above the title.";
    SGModRow *glass = SGOptionRow(@"Liquid Glass tracks", @"Each track on glass, the theme through glass under the cover", SGRKeyPlaylistGlass);
    return [[SGModPage alloc] initWithTitle:@"Playlists"
                                      intro:nil
                                   sections:@[SGSection(nil, @[fullCover, glass])]
                                     footer:@"Changes apply after restarting Spotify."];
}
