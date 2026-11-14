// Only the rows of a playlist's track list tell the index they laid out. The library's rows, the album page's
// and the list cells of Search and the artist page are left alone: the index belongs to playlists.
#import "Core/SGCore.h"
#import "AlphaIndex.h"

%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell
- (void)layoutSubviews {
    SGDebugOnce(@"hook Shared/AlphaIndex/AlphaIndexHooks.x: -[ElementCollectionViewCell layoutSubviews] first call");
    %orig;
    SGAlphaIndexNoteRow((UIView *)self);
}
%end

// The letters only line up with an alphabetical list, so the page's sorting adapter is handed over for the
// index to put the list in Spotify's Title order while the switch is on.
%hook _TtC35ListUXPlatform_FreeTierPlaylistImpl21FTPSortingAdapterImpl
- (instancetype)init {
    SGDebugOnce(@"hook Shared/AlphaIndex/AlphaIndexHooks.x: -[FTPSortingAdapterImpl init] first call");
    id adapter = %orig;
    SGAlphaIndexNoteSortAdapter(adapter);
    return adapter;
}
%end

%ctor {
    SGDebug(@"module Shared/AlphaIndex/AlphaIndexHooks.x on");
    if (!SGEnabled(SGKeyAlphaIndex)) return;
    %init;
    SGRequireClasses(@[@"_TtC35ListUXPlatform_FreeTierPlaylistImpl25ElementCollectionViewCell"]);
}
