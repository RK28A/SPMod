// The pages of Playlist Fusion (Fusion.h): its settings, the list where the destination and the sources are
// picked, and the list of playlists Fusion Shuffle never draws from. A role is said in words and a symbol
// beside its colour. Nothing is changed by picking: the merge runs from its own row, after two confirmations
// that spell out what is copied where and what leaves the library.
#import "Fusion.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"

static const CGFloat kTileGlyph = 18;

// A row's leading picture swapped for one of Fusion's own glyphs, in the colour the row is drawn in.
static void showGlyph(UITableViewCell *cell, SGFusionGlyph glyph, UIColor *color) {
    UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
    content.image = SGFusionIcon(glyph, 22);
    content.imageProperties.tintColor = color ?: UIColor.whiteColor;
    content.imageToTextPadding = 14;
    cell.contentConfiguration = content;
}

typedef NS_ENUM(NSInteger, SGFusionListKind) { SGFusionListMerge, SGFusionListExclude };

static NSArray<NSString *> *excludedIDs(void) {
    return [NSUserDefaults.standardUserDefaults stringArrayForKey:SGKeyFusionExcluded] ?: @[];
}

static void alert(NSString *title, NSString *message) {
    UIAlertController *box = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [box addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:box animated:YES completion:nil];
}

@interface SGFusionListPage : SGPage <UISearchBarDelegate>
- (instancetype)initWithKind:(SGFusionListKind)kind;
- (void)beginWithDestination:(NSString *)destination;
@end

@implementation SGFusionListPage {
    SGFusionListKind _kind;
    NSArray<SGFusionPlaylist *> *_all, *_shown;
    NSString *_error, *_filter;
    BOOL _loading, _running;
    NSString *_destination;
    NSMutableArray<NSString *> *_sources;
    NSMutableSet<NSString *> *_excluded;
    UIAlertController *_progress;
}

- (instancetype)initWithKind:(SGFusionListKind)kind {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _kind = kind;
        _sources = [NSMutableArray array];
        _excluded = [NSMutableSet setWithArray:excludedIDs()];
        self.title = kind == SGFusionListMerge ? @"Merge playlists" : @"Excluded playlists";
    }
    return self;
}

- (void)beginWithDestination:(NSString *)destination {
    _destination = [destination copy];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = SGPageBackground();
    UISearchBar *search = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 52)];
    search.searchBarStyle = UISearchBarStyleMinimal;
    search.placeholder = @"Search playlists";
    search.delegate = self;
    search.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.tableView.tableHeaderView = search;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self load];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGInsetForBars(self.tableView);
}

- (void)load {
    _loading = YES;
    _error = nil;
    [self.tableView reloadData];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionLoadPlaylists(^(NSArray<SGFusionPlaylist *> *playlists, NSString *error) {
        SGFusionListPage *page = weakSelf;
        if (!page) return;
        page->_loading = NO;
        page->_all = playlists;
        page->_error = error;
        // A destination handed in from a playlist's menu holds only if it can be added to.
        if (playlists && ![page playlistWithID:page->_destination].editable) page->_destination = nil;
        [page filter];
    });
}

- (void)filter {
    if (!_filter.length) {
        _shown = _all;
    } else {
        NSMutableArray<SGFusionPlaylist *> *kept = [NSMutableArray array];
        for (SGFusionPlaylist *playlist in _all) {
            if ([playlist.name rangeOfString:_filter options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [kept addObject:playlist];
        }
        _shown = kept;
    }
    [self.tableView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _filter = [searchText copy];
    [self filter];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (SGFusionPlaylist *)playlistWithID:(NSString *)identifier {
    for (SGFusionPlaylist *playlist in _all) {
        if ([playlist.identifier isEqualToString:identifier]) return playlist;
    }
    return nil;
}

// Excluded ids the library no longer has.
- (NSArray<NSString *> *)stale {
    if (_kind != SGFusionListExclude || !_all) return @[];
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    for (NSString *identifier in _excluded) {
        if (![self playlistWithID:identifier]) [gone addObject:identifier];
    }
    return [gone sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - table

// Merge: the action, then the playlists. Exclude: the playlists, then what is excluded and gone.
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (BOOL)isPlaylists:(NSInteger)section {
    return _kind == SGFusionListMerge ? section == 1 : section == 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isPlaylists:section]) return _shown.count ?: 1;
    return _kind == SGFusionListMerge ? 1 : (NSInteger)[self stale].count;
}

- (NSString *)countOf:(SGFusionPlaylist *)playlist {
    NSString *count = playlist.total >= 0 ? [NSString stringWithFormat:@"%ld tracks", (long)playlist.total] : @"";
    NSString *owner = playlist.owner.length ? playlist.owner : @"";
    NSString *joined = count.length && owner.length ? [NSString stringWithFormat:@"%@ · %@", count, owner] : count.length ? count : owner;
    return playlist.editable ? joined : [joined stringByAppendingString:joined.length ? @" · followed, source only" : @"Followed, source only"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = SGDequeueCell(tableView, @"fusion");
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    if (![self isPlaylists:indexPath.section]) {
        if (_kind == SGFusionListMerge) {
            BOOL ready = _destination && _sources.count && !_running;
            NSString *title = _running ? @"Merging…" : @"Merge";
            NSString *into = [self playlistWithID:_destination].name;
            NSString *subtitle = !_destination ? @"Pick a destination (green), then one or more sources (red)"
                : !_sources.count ? [NSString stringWithFormat:@"Into “%@”. Pick one or more sources (red)", into]
                : [NSString stringWithFormat:@"%lu source%@ into “%@”. Nothing changes before you confirm", (unsigned long)_sources.count, _sources.count == 1 ? @"" : @"s", into];
            SGFillCell(cell, title, subtitle, ready ? SGGreen() : SGGrey(), nil);
            showGlyph(cell, SGFusionGlyphMerge, ready ? SGGreen() : SGGrey());
        } else {
            NSString *identifier = [self stale][indexPath.row];
            SGFillCell(cell, @"No longer in your library", [NSString stringWithFormat:@"%@ · tap to forget", identifier], SGGrey(), @"questionmark.circle");
        }
        return cell;
    }
    if (!_shown.count) {
        NSString *title = _loading ? @"Reading your playlists…" : _error ? @"Could not read your playlists" : _filter.length ? @"No playlist by that name" : @"No playlists";
        SGFillCell(cell, title, _loading ? nil : _error ? [_error stringByAppendingString:@" Tap to try again."] : nil, SGGrey(), _loading ? @"hourglass" : @"exclamationmark.triangle");
        return cell;
    }
    SGFusionPlaylist *playlist = _shown[indexPath.row];
    NSString *details = [self countOf:playlist];
    if (_kind == SGFusionListExclude) {
        BOOL out = [_excluded containsObject:playlist.identifier];
        SGFillCell(cell, playlist.name, out ? [@"EXCLUDED · " stringByAppendingString:details] : details, out ? SGRed() : nil, out ? @"nosign" : @"music.note.list");
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", playlist.name, out ? @"excluded from Fusion Shuffle" : @"included"];
        return cell;
    }
    BOOL destination = [playlist.identifier isEqualToString:_destination];
    NSUInteger source = [_sources indexOfObject:playlist.identifier];
    if (destination) {
        SGFillCell(cell, playlist.name, [@"DESTINATION · " stringByAppendingString:details], SGGreen(), @"checkmark.circle.fill");
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, destination", playlist.name];
    } else if (source != NSNotFound) {
        SGFillCell(cell, playlist.name, [NSString stringWithFormat:@"SOURCE %lu · %@", (unsigned long)source + 1, details], SGRed(), @"minus.circle.fill");
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, source %lu, tap to remove", playlist.name, (unsigned long)source + 1];
    } else {
        SGFillCell(cell, playlist.name, details, playlist.editable ? nil : SGGrey(), @"music.note.list");
        cell.accessibilityLabel = [NSString stringWithFormat:@"%@, not selected", playlist.name];
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (![self isPlaylists:section]) return nil;
    return _kind == SGFusionListMerge
        ? @"The destination is a playlist you own or collaborate on. A playlist you follow can only be a source: its tracks are copied, and removing it afterwards unfollows it."
        : @"Fusion Shuffle never reads an excluded playlist. A track that is also in a playlist you allow can still play, from that one.";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (_running) return;
    if (![self isPlaylists:indexPath.section]) {
        if (_kind == SGFusionListMerge) {
            [self review];
        } else {
            NSArray<NSString *> *stale = [self stale];
            if (indexPath.row < (NSInteger)stale.count) [_excluded removeObject:stale[indexPath.row]];
            [self storeExcluded];
        }
        return;
    }
    if (!_shown.count) {
        if (!_loading) [self load];
        return;
    }
    SGFusionPlaylist *playlist = _shown[indexPath.row];
    if (_kind == SGFusionListExclude) {
        if ([_excluded containsObject:playlist.identifier]) [_excluded removeObject:playlist.identifier];
        else [_excluded addObject:playlist.identifier];
        [self storeExcluded];
        return;
    }
    if ([playlist.identifier isEqualToString:_destination]) return;
    if ([_sources containsObject:playlist.identifier]) {
        [_sources removeObject:playlist.identifier];
        [tableView reloadData];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:playlist.name
        message:playlist.editable ? nil : @"A playlist you follow: nothing can be added to it, so it can only be a source."
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak SGFusionListPage *weakSelf = self;
    if (playlist.editable) [sheet addAction:[UIAlertAction actionWithTitle:@"Destination (green): receives the tracks" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGFusionListPage *page = weakSelf;
        if (!page) return;
        page->_destination = playlist.identifier;
        [page->_sources removeObject:playlist.identifier];
        [page.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Source (red): its tracks are copied" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        SGFusionListPage *page = weakSelf;
        if (!page) return;
        [page->_sources addObject:playlist.identifier];
        [page.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    sheet.popoverPresentationController.sourceView = cell ?: tableView;
    sheet.popoverPresentationController.sourceRect = cell ? cell.bounds : CGRectMake(CGRectGetMidX(tableView.bounds), CGRectGetMidY(tableView.bounds), 0, 0);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)storeExcluded {
    [NSUserDefaults.standardUserDefaults setObject:[_excluded.allObjects sortedArrayUsingSelector:@selector(compare:)] forKey:SGKeyFusionExcluded];
    SGFusionShuffleForgetLibrary();
    [self.tableView reloadData];
}

#pragma mark - the merge

- (void)setRunning:(BOOL)running note:(NSString *)note {
    _running = running;
    if (running && !_progress) {
        _progress = [UIAlertController alertControllerWithTitle:@"Playlist Fusion" message:note preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:_progress animated:YES completion:nil];
    } else if (running) {
        _progress.message = note;
    }
    [self.tableView reloadData];
}

- (void)finish:(NSString *)title message:(NSString *)message retry:(void (^)(void))retry {
    _running = NO;
    [self.tableView reloadData];
    void (^show)(void) = ^{
        UIAlertController *box = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        if (retry) [box addAction:[UIAlertAction actionWithTitle:@"Try again" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { retry(); }]];
        [box addAction:[UIAlertAction actionWithTitle:retry ? @"Stop here" : @"OK" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:box animated:YES completion:nil];
    };
    UIAlertController *progress = _progress;
    _progress = nil;
    if (progress.presentingViewController) [progress dismissViewControllerAnimated:YES completion:show];
    else show();
}

// Reads the destination and every source, then says what would happen. Nothing is written here.
- (void)review {
    if (!_destination || !_sources.count) return;
    SGFusionPlaylist *destination = [self playlistWithID:_destination];
    NSArray<NSString *> *sources = [_sources copy];
    [self setRunning:YES note:@"Reading the playlists…"];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionLoadItems(destination.identifier, ^(NSArray<SGFusionItem *> *held, NSInteger unreadable, NSString *error) {
        if (!held) {
            [weakSelf finish:@"Nothing was changed" message:[NSString stringWithFormat:@"“%@” could not be read. %@", destination.name, error ?: @""] retry:nil];
            return;
        }
        [weakSelf readSources:sources at:0 into:[NSMutableArray array] skipped:0 destination:destination held:held];
    });
}

- (void)readSources:(NSArray<NSString *> *)sources at:(NSUInteger)index into:(NSMutableArray<NSString *> *)planned skipped:(NSInteger)skipped
        destination:(SGFusionPlaylist *)destination held:(NSArray<SGFusionItem *> *)held {
    if (index >= sources.count) {
        [self confirm:planned skipped:skipped sources:sources destination:destination held:held];
        return;
    }
    SGFusionPlaylist *source = [self playlistWithID:sources[index]];
    [self setRunning:YES note:[NSString stringWithFormat:@"Reading “%@” (%lu of %lu)…", source.name, (unsigned long)index + 1, (unsigned long)sources.count]];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionLoadItems(source.identifier, ^(NSArray<SGFusionItem *> *items, NSInteger unreadable, NSString *error) {
        if (!items) {
            [weakSelf finish:@"Nothing was changed" message:[NSString stringWithFormat:@"“%@” could not be read, so the merge was not started. %@", source.name, error ?: @""] retry:nil];
            return;
        }
        for (SGFusionItem *item in items) [planned addObject:item.uri];
        [weakSelf readSources:sources at:index + 1 into:planned skipped:skipped + unreadable destination:destination held:held];
    });
}

- (void)confirm:(NSArray<NSString *> *)planned skipped:(NSInteger)skipped sources:(NSArray<NSString *> *)sources
    destination:(SGFusionPlaylist *)destination held:(NSArray<SGFusionItem *> *)held {
    NSMutableArray<NSString *> *adding = [NSMutableArray array];
    NSInteger duplicates = 0;
    if (SGInt(SGKeyFusionDuplicates, 0) == 1) {
        NSMutableSet<NSString *> *present = [NSMutableSet set];
        for (SGFusionItem *item in held) [present addObject:item.uri];
        for (NSString *uri in planned) {
            if ([present containsObject:uri]) {
                duplicates++;
                continue;
            }
            [present addObject:uri];
            [adding addObject:uri];
        }
    } else {
        [adding addObjectsFromArray:planned];
    }
    // Local files and entries Spotify no longer has cannot be copied: with any, the sources stay.
    BOOL keep = SGEnabled(SGKeyFusionKeepSources) || skipped > 0;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *identifier in sources) [names addObject:[NSString stringWithFormat:@"“%@”", [self playlistWithID:identifier].name]];
    NSString *list = [names componentsJoinedByString:@", "];
    NSMutableString *message = [NSMutableString stringWithFormat:@"%lu tracks from %lu red playlist%@ (%@) will be added to the end of “%@”, in order. It has %lu now and will have %lu.",
        (unsigned long)adding.count, (unsigned long)sources.count, sources.count == 1 ? @"" : @"s", list, destination.name,
        (unsigned long)held.count, (unsigned long)(held.count + adding.count)];
    if (duplicates) [message appendFormat:@"\n\n%ld already in the destination will be skipped.", (long)duplicates];
    if (skipped) [message appendFormat:@"\n\n%ld local or unavailable entries cannot be copied. Because of them the red playlists will be kept.", (long)skipped];
    if (keep) [message appendString:@"\n\nThe red playlists stay in your library."];
    else [message appendFormat:@"\n\nOnce every track is read back from “%@”, the red playlists (%@) will be removed from your library. Spotify cannot delete a playlist: they are unfollowed, and stay for anyone else who follows them. This can be hard to undo.", destination.name, list];
    if (!adding.count) {
        [self finish:@"Nothing to add" message:@"Every track of the red playlists is already in the destination, or none can be copied. Nothing was changed." retry:nil];
        return;
    }
    __weak SGFusionListPage *weakSelf = self;
    void (^second)(void) = ^{
        NSString *last = keep ? [NSString stringWithFormat:@"Add %lu tracks to “%@”?", (unsigned long)adding.count, destination.name]
            : [NSString stringWithFormat:@"Add %lu tracks to “%@”, then remove %@ from your library?", (unsigned long)adding.count, destination.name, list];
        UIAlertController *box = [UIAlertController alertControllerWithTitle:@"Confirm the fusion" message:last preferredStyle:UIAlertControllerStyleAlert];
        [box addAction:[UIAlertAction actionWithTitle:@"Confirm the fusion" style:keep ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [weakSelf add:adding from:0 sources:sources destination:destination before:held keep:keep];
        }]];
        [box addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:box animated:YES completion:nil];
    };
    _running = NO;
    [self.tableView reloadData];
    UIAlertController *progress = _progress;
    _progress = nil;
    void (^first)(void) = ^{
        UIAlertController *box = [UIAlertController alertControllerWithTitle:@"Playlist Fusion" message:message preferredStyle:UIAlertControllerStyleAlert];
        [box addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { second(); }]];
        [box addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        [weakSelf presentViewController:box animated:YES completion:nil];
    };
    if (progress.presentingViewController) [progress dismissViewControllerAnimated:YES completion:first];
    else first();
}

- (void)add:(NSArray<NSString *> *)adding from:(NSUInteger)from sources:(NSArray<NSString *> *)sources
destination:(SGFusionPlaylist *)destination before:(NSArray<SGFusionItem *> *)before keep:(BOOL)keep {
    [self setRunning:YES note:[NSString stringWithFormat:@"Adding… %lu of %lu", (unsigned long)from, (unsigned long)adding.count]];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionAddItems(destination.identifier, adding, from, ^(NSUInteger added) {
        [weakSelf setRunning:YES note:[NSString stringWithFormat:@"Adding… %lu of %lu", (unsigned long)added, (unsigned long)adding.count]];
    }, ^(NSUInteger added, NSString *error) {
        if (error) {
            NSString *message = [NSString stringWithFormat:@"%lu of %lu tracks were added to “%@”. No playlist was removed. %@\n\nTrying again goes on from track %lu, without adding the first ones twice.",
                (unsigned long)added, (unsigned long)adding.count, destination.name, error, (unsigned long)added + 1];
            [weakSelf finish:@"The merge stopped" message:message retry:^{
                [weakSelf add:adding from:added sources:sources destination:destination before:before keep:keep];
            }];
            return;
        }
        [weakSelf verify:adding sources:sources destination:destination before:before keep:keep];
    });
}

// The destination read back: each track must be there at least as many times as before plus as many as were added.
- (void)verify:(NSArray<NSString *> *)adding sources:(NSArray<NSString *> *)sources destination:(SGFusionPlaylist *)destination
        before:(NSArray<SGFusionItem *> *)before keep:(BOOL)keep {
    [self setRunning:YES note:@"Checking the destination…"];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionLoadItems(destination.identifier, ^(NSArray<SGFusionItem *> *now, NSInteger unreadable, NSString *error) {
        NSCountedSet<NSString *> *wanted = [NSCountedSet set], *present = [NSCountedSet set];
        for (SGFusionItem *item in before) [wanted addObject:item.uri];
        for (NSString *uri in adding) [wanted addObject:uri];
        for (SGFusionItem *item in now) [present addObject:item.uri];
        NSUInteger missing = 0;
        for (NSString *uri in wanted) {
            NSUInteger want = [wanted countForObject:uri], have = [present countForObject:uri];
            if (have < want) missing += want - have;
        }
        if (!now || missing) {
            NSString *why = now ? [NSString stringWithFormat:@"%lu tracks could not be found in “%@” afterwards.", (unsigned long)missing, destination.name]
                                : [NSString stringWithFormat:@"“%@” could not be read back. %@", destination.name, error ?: @""];
            [weakSelf finish:@"Added, not confirmed" message:[why stringByAppendingString:@" The red playlists were kept."] retry:nil];
            return;
        }
        if (keep) {
            [weakSelf done:[NSString stringWithFormat:@"%lu tracks were added to “%@” and read back from it. The red playlists were kept.", (unsigned long)adding.count, destination.name]];
            return;
        }
        [weakSelf remove:sources at:0 failed:[NSMutableArray array] added:adding.count destination:destination];
    });
}

- (void)remove:(NSArray<NSString *> *)sources at:(NSUInteger)index failed:(NSMutableArray<NSString *> *)failed added:(NSUInteger)added
   destination:(SGFusionPlaylist *)destination {
    if (index >= sources.count) {
        NSString *message = [NSString stringWithFormat:@"%lu tracks were added to “%@” and read back from it. %lu red playlist%@ left your library.",
            (unsigned long)added, destination.name, (unsigned long)(sources.count - failed.count), sources.count - failed.count == 1 ? @"" : @"s"];
        if (failed.count) message = [message stringByAppendingFormat:@" Still in it, Spotify refused: %@.", [failed componentsJoinedByString:@", "]];
        [self done:message];
        return;
    }
    SGFusionPlaylist *source = [self playlistWithID:sources[index]];
    [self setRunning:YES note:[NSString stringWithFormat:@"Removing “%@” from your library…", source.name]];
    __weak SGFusionListPage *weakSelf = self;
    SGFusionRemoveFromLibrary(source.identifier, ^(NSString *error) {
        if (error) [failed addObject:[NSString stringWithFormat:@"“%@”", source.name]];
        [weakSelf remove:sources at:index + 1 failed:failed added:added destination:destination];
    });
}

- (void)done:(NSString *)message {
    _destination = nil;
    [_sources removeAllObjects];
    SGFusionShuffleForgetLibrary();
    [self finish:@"Fusion done" message:message retry:nil];
    [self load];
}

@end

UIViewController *SGFusionMergePage(NSString *destination) {
    SGFusionListPage *page = [[SGFusionListPage alloc] initWithKind:SGFusionListMerge];
    [page beginWithDestination:destination];
    return page;
}

#pragma mark - settings

UIViewController *SGFusionSettingsPage(void) {
    SGModRow *shuffle = SGStatActionRow(@"Fusion Shuffle", @"Mixes the tracks of every playlist you allow. No playlist is made or changed",
        ^NSString *{
            // The whole status squeezed the row's title into a column: the row says on or off, the sheet says the rest.
            if (SGFusionShuffleActive()) return @"On";
            NSString *status = SGFusionShuffleStatus();
            return [status hasPrefix:@"Reading"] ? @"Reading…" : [status isEqualToString:@"Off"] || !status.length ? @"Off" : @"Didn't start";
        }, ^{
            if (SGFusionShuffleActive()) SGFusionShuffleStop();
            else SGFusionShuffleStart();
        });
    shuffle.refreshOn = SGFusionShuffleDidChangeNotification;
    SGModRow *excluded = SGPageRow(@"Excluded playlists", ^UIViewController *{ return [[SGFusionListPage alloc] initWithKind:SGFusionListExclude]; });
    excluded.value = ^NSString *{
        NSUInteger count = excludedIDs().count;
        return count ? @(count).stringValue : @"None";
    };
    SGModRow *icon = SGChoiceRow(@"Fusion Shuffle icon", nil, SGKeyFusionIcon, @[@"Arrows with earrings", @"Earrings on the arrows"], 0);
    icon.choiceNotes = @[@"The shuffle arrows with a pair of earrings at their corner.", @"The pair of earrings hanging from the arrows."];
    icon.choiceImages = @[SGFusionShuffleIcon(0, kTileGlyph), SGFusionShuffleIcon(1, kTileGlyph)];
    // The buttons showing it take the new one at once.
    icon.chosen = ^(NSInteger index) {
        shuffle.image = SGFusionShuffleIcon(index, kTileGlyph);
        [NSNotificationCenter.defaultCenter postNotificationName:SGFusionShuffleDidChangeNotification object:nil];
    };
    SGModRow *sampling = SGChoiceRow(@"Track sampling", nil, SGKeyFusionSampling, @[@"Equal chance per track", @"Equal chance per playlist"], 0);
    sampling.choiceNotes = @[@"A long playlist is heard more than a short one.", @"Every playlist is heard as often, whatever its length."];
    SGModRow *window = SGSliderRow(@"Recent tracks avoided", nil, 5, 100, 5,
        ^double { return SGInt(SGKeyFusionRecentWindow, 20); },
        ^(double value) { SGSetInt(SGKeyFusionRecentWindow, (NSInteger)value); },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%d", (int)value]; });
    window.visible = ^BOOL { return SGEnabled(SGKeyFusionAvoidRecent); };
    SGModRow *refresh = SGActionRow(@"Refresh library", @"Read the playlists again the next time Fusion Shuffle starts", ^{
        SGFusionShuffleForgetLibrary();
        alert(@"Refresh library", @"The playlists are read again the next time Fusion Shuffle starts. They are also read again after half an hour.");
    });
    SGModRow *merge = SGPageRow(@"Merge playlists", ^UIViewController *{ return [[SGFusionListPage alloc] initWithKind:SGFusionListMerge]; });
    SGModRow *duplicates = SGChoiceRow(@"Duplicates", nil, SGKeyFusionDuplicates, @[@"Preserve all entries", @"Skip destination duplicates"], 0);
    duplicates.choiceNotes = @[@"Every entry of the red playlists is copied, even one the destination already has.",
                               @"A track the destination already has, or that came from an earlier red playlist, is not added again."];
    SGModRow *keep = SGSwitchRow(@"Keep red playlists after copying", @"Off: once every track is read back from the destination, the red playlists are removed from your library", SGKeyFusionKeepSources);
    SGModRow *confirm = SGStatRow(@"Double confirmation", ^NSString *{ return @"Always"; });
    return [[SGModPage alloc] initWithTitle:@"Playlist Fusion" intro:nil sections:@[
        SGNotedSection(@"Fusion Shuffle", @[
            SGWithImage(shuffle, SGFusionIcon(SGFusionGlyphFusion, kTileGlyph)),
            SGWithSymbol(icon, @"paintbrush"),
            SGWithSymbol(excluded, @"nosign"),
            SGWithSymbol(SGSwitchRow(@"Deduplicate tracks", @"A track in several playlists counts once", SGKeyFusionDedupe), @"square.on.square"),
            SGWithSymbol(sampling, @"dice"),
            SGWithSymbol(SGSwitchRow(@"Avoid recently played tracks", @"Unless too few would be left", SGKeyFusionAvoidRecent), @"clock.arrow.circlepath"),
            window,
            SGWithSymbol(SGSwitchRow(@"Allow explicit tracks", @"A track read through Spotify's own endpoints is never known to be explicit", SGKeyFusionExplicit), @"e.square"),
            SGWithSymbol(refresh, @"arrow.clockwise"),
        ], @"Starts one track and feeds Spotify's queue with the rest, so it stops when you play something else. Tracks already queued stay in the queue. A playlist Spotify does not give the items of is passed over and counted as not readable."),
        SGNotedSection(@"Playlist Fusion", @[
            SGWithImage(merge, SGFusionIcon(SGFusionGlyphMerge, kTileGlyph)),
            SGWithSymbol(duplicates, @"doc.on.doc"),
            SGWithSymbol(keep, @"tray.full"),
            SGWithSymbol(confirm, @"checkmark.shield"),
        ], @"Copies the red playlists onto the end of the green one. Spotify cannot delete a playlist: removing one unfollows it. Excluded playlists above do not limit a merge."),
    ] footer:nil];
}
