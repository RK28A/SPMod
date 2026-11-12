// Spotify's Web API as the signed-in app, with the authorization the app sends its own requests
// (SGSpclientHeaders). Two shapes are tried where the API changed in February 2026: a playlist's entries are
// under /items with each entry's `item`, before that under /tracks with `track`, and a playlist leaves the
// library through DELETE /me/library, before that through its /followers.
#import "Fusion.h"
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"

static NSString *const kAPI = @"https://api.spotify.com/v1";
static const NSTimeInterval kHeadersWait = 8;
static const int kRetries = 3;

@implementation SGFusionPlaylist
@end

@implementation SGFusionItem
@end

static void onMain(void (^block)(void)) {
    dispatch_async(dispatch_get_main_queue(), block);
}

static NSString *explain(NSInteger status) {
    switch (status) {
        case 0: return @"Spotify could not be reached. Play something first so the app signs its requests, then try again.";
        case 401: return @"Spotify turned the request down (401): the session's key has run out. Play a song and try again.";
        case 403: return @"Spotify does not allow this for this playlist or this account (403).";
        case 404: return @"Spotify does not know this playlist any more (404).";
        case 429: return @"Spotify asked to slow down (429). Wait a minute and try again.";
        default: return [NSString stringWithFormat:@"Spotify answered with an error (%ld).", (long)status];
    }
}

static void send(NSString *method, NSString *url, id body, int triesLeft, void (^done)(NSInteger status, id json)) {
    __block BOOL answered = NO;
    void (^once)(NSInteger, id) = ^(NSInteger status, id json) {
        onMain(^{
            if (answered) return;
            answered = YES;
            done(status, json);
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHeadersWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!SGKaraokeSpotifyAuthorization().length) once(0, nil);
    });
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        NSString *authorization = headers[@"authorization"];
        NSURL *address = [NSURL URLWithString:url];
        if (!authorization.length || !address) {
            once(0, nil);
            return;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:address];
        request.HTTPMethod = method;
        request.timeoutInterval = 30;
        [request setValue:authorization forHTTPHeaderField:@"Authorization"];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        if (body) {
            request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        }
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            NSInteger status = http.statusCode;
            if (status == 429 && triesLeft > 0) {
                double wait = MIN(15, MAX(1, [[http valueForHTTPHeaderField:@"Retry-After"] doubleValue]));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    send(method, url, body, triesLeft - 1, done);
                });
                answered = YES;
                return;
            }
            id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            once(status, json);
        }] resume];
    });
}

static BOOL fine(NSInteger status) {
    return status >= 200 && status < 300;
}

static NSString *text(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSDictionary *record(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

#pragma mark - the library's playlists

static NSString *const kNamesKey = @"spotifyglass.fusion.names";
static BOOL sg_warmed;

// A name two playlists share tells neither apart: it is kept with no id.
static void rememberNames(NSArray<SGFusionPlaylist *> *playlists) {
    NSMutableDictionary<NSString *, NSString *> *names = [NSMutableDictionary dictionary];
    for (SGFusionPlaylist *playlist in playlists) names[playlist.name] = names[playlist.name] ? @"" : playlist.identifier;
    [NSUserDefaults.standardUserDefaults setObject:names forKey:kNamesKey];
    sg_warmed = YES;
}

NSString *SGFusionPlaylistNamed(NSString *name) {
    if (!name.length) return nil;
    NSString *identifier = [NSUserDefaults.standardUserDefaults dictionaryForKey:kNamesKey][name];
    return [identifier isKindOfClass:NSString.class] && identifier.length ? identifier : nil;
}

void SGFusionWarmNames(void (^done)(void)) {
    static BOOL asking;
    if (sg_warmed || asking) return;
    asking = YES;
    SGFusionLoadPlaylists(^(NSArray<SGFusionPlaylist *> *playlists, NSString *error) {
        asking = NO;
        // Asked once a launch, read or not: a menu does not ask again each time it lays itself out.
        sg_warmed = YES;
        if (playlists && done) done();
    });
}

static void playlistsPage(NSString *me, NSUInteger offset, NSMutableArray<SGFusionPlaylist *> *found,
                          void (^done)(NSArray<SGFusionPlaylist *> *, NSString *)) {
    NSString *url = [NSString stringWithFormat:@"%@/me/playlists?limit=50&offset=%lu", kAPI, (unsigned long)offset];
    send(@"GET", url, nil, kRetries, ^(NSInteger status, id json) {
        NSArray *entries = [record(json)[@"items"] isKindOfClass:NSArray.class] ? json[@"items"] : nil;
        if (!fine(status) || !entries) {
            done(nil, explain(status));
            return;
        }
        for (id entry in entries) {
            NSDictionary *playlist = record(entry);
            NSString *identifier = text(playlist[@"id"]);
            if (!identifier.length) continue;
            SGFusionPlaylist *one = [SGFusionPlaylist new];
            one.identifier = identifier;
            one.name = text(playlist[@"name"]).length ? playlist[@"name"] : @"Untitled playlist";
            NSDictionary *owner = record(playlist[@"owner"]);
            one.owner = text(owner[@"display_name"]) ?: text(owner[@"id"]) ?: @"";
            NSDictionary *count = record(playlist[@"items"]) ?: record(playlist[@"tracks"]);
            one.total = [count[@"total"] respondsToSelector:@selector(integerValue)] ? [count[@"total"] integerValue] : -1;
            BOOL mine = me.length && [text(owner[@"id"]) isEqualToString:me];
            one.editable = mine || [playlist[@"collaborative"] isEqual:@YES];
            [found addObject:one];
        }
        if (entries.count < 50 || !text(record(json)[@"next"]).length) {
            rememberNames(found);
            done(found, nil);
        }
        else playlistsPage(me, offset + entries.count, found, done);
    });
}

void SGFusionLoadPlaylists(void (^done)(NSArray<SGFusionPlaylist *> *, NSString *)) {
    send(@"GET", [kAPI stringByAppendingString:@"/me"], nil, kRetries, ^(NSInteger status, id json) {
        NSString *me = text(record(json)[@"id"]);
        if (!fine(status) || !me.length) {
            done(nil, explain(status));
            return;
        }
        playlistsPage(me, 0, [NSMutableArray array], done);
    });
}

#pragma mark - a playlist's items

static void itemsPage(NSString *playlist, NSString *shape, NSUInteger offset, NSMutableArray<SGFusionItem *> *found, NSInteger unreadable,
                      void (^done)(NSArray<SGFusionItem *> *, NSInteger, NSString *)) {
    NSString *url = [NSString stringWithFormat:@"%@/playlists/%@/%@?limit=100&offset=%lu", kAPI, playlist, shape, (unsigned long)offset];
    send(@"GET", url, nil, kRetries, ^(NSInteger status, id json) {
        NSArray *entries = [record(json)[@"items"] isKindOfClass:NSArray.class] ? json[@"items"] : nil;
        if (!fine(status) || !entries) {
            // The older shape, once, before anything was read under the newer one.
            if (offset == 0 && [shape isEqualToString:@"items"] && status != 0 && status != 401 && status != 429) {
                itemsPage(playlist, @"tracks", 0, found, unreadable, done);
                return;
            }
            done(nil, 0, fine(status) ? @"Spotify did not give this playlist's items: it only does for playlists you own or collaborate on." : explain(status));
            return;
        }
        NSInteger skipped = unreadable;
        for (id entry in entries) {
            NSDictionary *item = record(record(entry)[@"item"]) ?: record(record(entry)[@"track"]);
            NSString *uri = text(item[@"uri"]);
            // A file of the user's own, or an entry Spotify no longer has: nothing the API can add elsewhere.
            if (!uri.length || [uri hasPrefix:@"spotify:local:"] || [item[@"is_local"] isEqual:@YES]) {
                skipped++;
                continue;
            }
            SGFusionItem *one = [SGFusionItem new];
            one.uri = uri;
            one.isTrack = [uri hasPrefix:@"spotify:track:"];
            one.isExplicit = [item[@"explicit"] isEqual:@YES];
            [found addObject:one];
        }
        NSInteger total = [record(json)[@"total"] respondsToSelector:@selector(integerValue)] ? [json[@"total"] integerValue] : -1;
        NSUInteger read = offset + entries.count;
        if (entries.count == 0 || (total >= 0 && (NSInteger)read >= total) || (total < 0 && entries.count < 100)) {
            if (total >= 0 && (NSInteger)read < total) done(nil, 0, @"Spotify stopped short of the playlist's end. Nothing was changed.");
            else done(found, skipped, nil);
            return;
        }
        itemsPage(playlist, shape, read, found, skipped, done);
    });
}

void SGFusionLoadItems(NSString *playlist, void (^done)(NSArray<SGFusionItem *> *, NSInteger, NSString *)) {
    itemsPage(playlist, @"items", 0, [NSMutableArray array], 0, done);
}

#pragma mark - changes

static void addBatch(NSString *playlist, NSString *shape, NSArray<NSString *> *uris, NSUInteger from,
                     void (^progress)(NSUInteger), void (^done)(NSUInteger, NSString *)) {
    if (from >= uris.count) {
        done(uris.count, nil);
        return;
    }
    NSArray<NSString *> *batch = [uris subarrayWithRange:NSMakeRange(from, MIN((NSUInteger)100, uris.count - from))];
    NSString *url = [NSString stringWithFormat:@"%@/playlists/%@/%@", kAPI, playlist, shape];
    send(@"POST", url, @{@"uris": batch}, kRetries, ^(NSInteger status, id json) {
        if (!fine(status)) {
            if (from == 0 && [shape isEqualToString:@"items"] && (status == 404 || status == 405)) {
                addBatch(playlist, @"tracks", uris, from, progress, done);
                return;
            }
            done(from, explain(status));
            return;
        }
        NSUInteger added = from + batch.count;
        if (progress) progress(added);
        addBatch(playlist, shape, uris, added, progress, done);
    });
}

void SGFusionAddItems(NSString *playlist, NSArray<NSString *> *uris, NSUInteger from,
                      void (^progress)(NSUInteger), void (^done)(NSUInteger, NSString *)) {
    addBatch(playlist, @"items", uris, from, progress, done);
}

void SGFusionRemoveFromLibrary(NSString *playlist, void (^done)(NSString *)) {
    NSString *uri = [@"spotify:playlist:" stringByAppendingString:playlist];
    NSString *escaped = [uri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    send(@"DELETE", [NSString stringWithFormat:@"%@/me/library?uris=%@", kAPI, escaped], nil, kRetries, ^(NSInteger status, id json) {
        if (fine(status)) {
            done(nil);
            return;
        }
        send(@"DELETE", [NSString stringWithFormat:@"%@/playlists/%@/followers", kAPI, playlist], nil, kRetries, ^(NSInteger older, id reply) {
            done(fine(older) ? nil : explain(older ?: status));
        });
    });
}
