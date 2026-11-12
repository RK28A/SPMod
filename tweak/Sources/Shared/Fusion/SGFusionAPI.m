// Playlist Fusion's and Fusion Shuffle's reading and writing (Fusion.h), as the signed-in app, with the
// authorization the app sends its own requests (SGSpclientHeaders). Two doors, and the log says which a call
// went through and what came back ("fusion: GET api/v1/me -> 200").
//
// The Web API first. Two shapes are tried where it changed in February 2026: a playlist's entries are under
// /items with each entry's `item`, before that under /tracks with `track`, and a playlist leaves the library
// through DELETE /me/library, before that through its /followers. It only gives the items of playlists the
// user owns or collaborates on, and it turns the app's own key away on some accounts (403, or 429 for hours).
//
// Then the endpoints Spotify's own apps keep playlists through, /playlist/v2 on the host the app talks to,
// asked for JSON: the library is the account's rootlist, a playlist is its list of uris, and both are changed
// by posting a list of operations to their /changes. These give followed playlists too. They say nothing of
// a track but its uri, so a track read this way is never known to be explicit. They are not documented:
// what is sent and read here is what Spotify's web player sends and reads, and an answer of another shape is
// logged with the names it did have. Three refusals with no answer ever understood and they are left alone
// for the rest of the launch.
#import "Fusion.h"
#import "Core/SGCore.h"
#import "Shared/Lyrics/Lyrics.h"

static NSString *const kAPI = @"https://api.spotify.com/v1";
static NSString *const kMeKey = @"spotifyglass.fusion.me";
static const NSTimeInterval kHeadersWait = 8;
static const int kRetries = 3, kInnerLossLimit = 3, kInnerPage = 500;
// What stands where a status would when there is none: no answer at all, an answer without what was asked
// for, one that stopped before the end, no account to ask about, a door not gone through.
enum { kNoAnswer = 0, kNoItems = -1, kShort = -2, kNoAccount = -3, kUntried = -4 };

@implementation SGFusionPlaylist
@end

@implementation SGFusionItem
@end

static void onMain(void (^block)(void)) {
    dispatch_async(dispatch_get_main_queue(), block);
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

static NSArray *list(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

// A count, which the inner endpoints write as a number or as a string of one; -1 when there is none.
static NSInteger count(id value) {
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : -1;
}

static NSString *explain(NSInteger status) {
    switch (status) {
        case kNoAnswer: return @"Spotify could not be reached. Play something first so the app signs its requests, then try again.";
        case kNoItems: return @"Spotify answered without what was asked for.";
        case kShort: return @"Spotify stopped short of the playlist's end. Nothing was changed.";
        case kUntried: return @"Spotify turned the app's key away, and its own endpoints did not answer as expected.";
        case kNoAccount: return @"The account's name is not known yet. Open Your Library once, then try again.";
        case 401: return @"Spotify turned the request down (401): the session's key has run out. Play a song and try again.";
        case 403: return @"Spotify does not allow this for this playlist or this account (403).";
        case 404: return @"Spotify does not know this playlist any more (404).";
        case 429: return @"Spotify asked to slow down (429). Wait a minute and try again.";
        default: return [NSString stringWithFormat:@"Spotify answered with an error (%ld).", (long)status];
    }
}

// What to say once both doors were tried, or only one.
static NSString *both(NSInteger web, NSInteger inner) {
    if (web == kUntried) return explain(inner);
    if (inner == kUntried) return explain(web);
    return [NSString stringWithFormat:@"%@ Spotify's own endpoint was tried too (%ld).", explain(web), (long)inner];
}

static int sg_innerLosses;
static BOOL sg_innerWorked;

// `inner`: one of Spotify's own endpoints, with every header the app sends there; else the Web API, with the
// authorization alone.
static void send(BOOL inner, NSString *method, NSString *url, id body, int triesLeft, void (^done)(NSInteger status, id json)) {
    if (inner && !sg_innerWorked && sg_innerLosses >= kInnerLossLimit) {
        onMain(^{ done(kUntried, nil); });
        return;
    }
    __block BOOL answered = NO;
    void (^once)(NSInteger, id) = ^(NSInteger status, id json) {
        onMain(^{
            if (answered) return;
            answered = YES;
            SGLog(@"fusion: %@ %@%@ -> %ld", method, inner ? @"spclient" : @"api", [NSURL URLWithString:url].path ?: @"", (long)status);
            if (inner && fine(status)) sg_innerWorked = YES;
            else if (inner && status != kNoAnswer) sg_innerLosses++;
            done(status, json);
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHeadersWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!SGKaraokeSpotifyAuthorization().length) once(kNoAnswer, nil);
    });
    SGSpclientHeaders(^(NSDictionary<NSString *, NSString *> *headers) {
        NSString *authorization = headers[@"authorization"];
        NSURL *address = [NSURL URLWithString:url];
        if (!authorization.length || !address) {
            once(kNoAnswer, nil);
            return;
        }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:address];
        request.HTTPMethod = method;
        request.timeoutInterval = 30;
        if (inner) {
            for (NSString *name in headers) [request setValue:headers[name] forHTTPHeaderField:name];
        } else {
            [request setValue:authorization forHTTPHeaderField:@"Authorization"];
        }
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        if (body) {
            request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        }
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
            NSInteger status = http.statusCode;
            if (status == 429 && triesLeft > 0) {
                double wait = MIN(8, MAX(1, [[http valueForHTTPHeaderField:@"Retry-After"] doubleValue]));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(wait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    send(inner, method, url, body, triesLeft - 1, done);
                });
                return;
            }
            id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            once(status, json);
        }] resume];
    });
}

static NSString *innerURL(NSString *path) {
    return [NSString stringWithFormat:@"https://%@%@", SGSpclientHost(), path];
}

// The Web API having turned the app's key away (403, 429 past its retries): the rest of the launch goes
// straight through Spotify's own endpoints.
static BOOL sg_webShut;
// The account, as the Web API named it this launch, else as the app's own requests did, else as last known.
static NSString *sg_me;
// The playlists the Web API listed as someone else's: it will not give their items, so it is not asked.
static NSSet<NSString *> *sg_followed;

static NSString *account(void) {
    return sg_me ?: SGSpclientUsername() ?: [NSUserDefaults.standardUserDefaults stringForKey:kMeKey];
}

static NSString *escaped(NSString *part) {
    return [part stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet] ?: part;
}

#pragma mark - the library's playlists, the Web API

static void webPlaylistsPage(NSString *me, NSUInteger offset, NSMutableArray<SGFusionPlaylist *> *found,
                             void (^done)(NSArray<SGFusionPlaylist *> *, NSInteger)) {
    NSString *url = [NSString stringWithFormat:@"%@/me/playlists?limit=50&offset=%lu", kAPI, (unsigned long)offset];
    send(NO, @"GET", url, nil, kRetries, ^(NSInteger status, id json) {
        NSArray *entries = list(record(json)[@"items"]);
        if (!fine(status) || !entries) {
            done(nil, fine(status) ? kNoItems : status);
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
            NSDictionary *held = record(playlist[@"items"]) ?: record(playlist[@"tracks"]);
            one.total = count(held[@"total"]);
            BOOL mine = me.length && [text(owner[@"id"]) isEqualToString:me];
            one.editable = mine || [playlist[@"collaborative"] isEqual:@YES];
            [found addObject:one];
        }
        if (entries.count < 50 || !text(record(json)[@"next"]).length) done(found, status);
        else webPlaylistsPage(me, offset + entries.count, found, done);
    });
}

static void webPlaylists(void (^done)(NSArray<SGFusionPlaylist *> *, NSInteger)) {
    send(NO, @"GET", [kAPI stringByAppendingString:@"/me"], nil, kRetries, ^(NSInteger status, id json) {
        NSString *me = text(record(json)[@"id"]);
        if (!fine(status) || !me.length) {
            done(nil, fine(status) ? kNoItems : status);
            return;
        }
        sg_me = [me copy];
        [NSUserDefaults.standardUserDefaults setObject:me forKey:kMeKey];
        webPlaylistsPage(me, 0, [NSMutableArray array], done);
    });
}

#pragma mark - the library's playlists, Spotify's own endpoint

// The rootlist: `contents.items` are the library's entries in order, playlists and the marks that open and
// close a folder, and `contents.metaItems` says of each, at the same place, its name, length and owner.
static void innerPlaylistsPage(NSString *user, NSUInteger from, NSMutableArray<SGFusionPlaylist *> *found,
                               void (^done)(NSArray<SGFusionPlaylist *> *, NSInteger)) {
    NSMutableString *path = [NSMutableString stringWithFormat:@"/playlist/v2/user/%@/rootlist?decorate=revision,attributes,length,owner,capabilities", escaped(user)];
    if (from) [path appendFormat:@"&from=%lu&length=%d", (unsigned long)from, kInnerPage];
    send(YES, @"GET", innerURL(path), nil, kRetries, ^(NSInteger status, id json) {
        NSDictionary *answer = record(json), *contents = record(answer[@"contents"]);
        if (!fine(status) || !answer) {
            done(nil, fine(status) ? kNoItems : status);
            return;
        }
        NSArray *entries = list(contents[@"items"]) ?: @[], *about = list(contents[@"metaItems"]);
        // A window asked for further on and answered from the start: the paging is not what is thought here.
        if (from && count(contents[@"pos"]) != (NSInteger)from) {
            SGLog(@"fusion: the rootlist's window at %lu came back at %ld", (unsigned long)from, (long)count(contents[@"pos"]));
            done(nil, kShort);
            return;
        }
        NSUInteger nameless = 0;
        for (NSUInteger i = 0; i < entries.count; i++) {
            NSString *uri = text(record(entries[i])[@"uri"]);
            NSRange marker = [uri rangeOfString:@"playlist:" options:NSBackwardsSearch];
            if (![uri hasPrefix:@"spotify:"] || marker.location == NSNotFound || [uri containsString:@"-group:"]) continue;
            NSDictionary *said = i < about.count ? record(about[i]) : nil;
            SGFusionPlaylist *one = [SGFusionPlaylist new];
            one.identifier = [uri substringFromIndex:NSMaxRange(marker)];
            NSString *name = text(record(said[@"attributes"])[@"name"]);
            if (!name.length) nameless++;
            one.name = name.length ? name : @"Untitled playlist";
            one.owner = text(said[@"ownerUsername"]) ?: @"";
            one.total = count(said[@"length"]);
            NSDictionary *can = record(said[@"capabilities"]);
            one.editable = can ? [can[@"canEditItems"] isEqual:@YES] : [one.owner isEqualToString:user];
            if (one.identifier.length) [found addObject:one];
        }
        if (from == 0) SGLog(@"fusion: the rootlist has %@ (%lu entries here, %lu playlists nameless)",
                             [answer.allKeys componentsJoinedByString:@","], (unsigned long)entries.count, (unsigned long)nameless);
        if ([contents[@"truncated"] isEqual:@YES] && entries.count) innerPlaylistsPage(user, from + entries.count, found, done);
        else done(found, status);
    });
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

void SGFusionLoadPlaylists(void (^done)(NSArray<SGFusionPlaylist *> *, NSString *)) {
    void (^inner)(NSInteger) = ^(NSInteger web) {
        NSString *user = account();
        if (!user.length) {
            SGLog(@"fusion: no account name to ask Spotify's own endpoint with");
            done(nil, web == kUntried ? explain(kNoAccount) : explain(web));
            return;
        }
        innerPlaylistsPage(user, 0, [NSMutableArray array], ^(NSArray<SGFusionPlaylist *> *playlists, NSInteger status) {
            if (!playlists) {
                done(nil, both(web, status));
                return;
            }
            sg_followed = nil;
            rememberNames(playlists);
            done(playlists, nil);
        });
    };
    if (sg_webShut) {
        inner(kUntried);
        return;
    }
    webPlaylists(^(NSArray<SGFusionPlaylist *> *playlists, NSInteger status) {
        if (!playlists) {
            if (status == 403 || status == 429) sg_webShut = YES;
            inner(status);
            return;
        }
        NSMutableSet<NSString *> *followed = [NSMutableSet set];
        for (SGFusionPlaylist *playlist in playlists) {
            if (!playlist.editable) [followed addObject:playlist.identifier];
        }
        sg_followed = followed;
        rememberNames(playlists);
        done(playlists, nil);
    });
}

#pragma mark - a playlist's items

static void webItemsPage(NSString *playlist, NSString *shape, NSUInteger offset, NSMutableArray<SGFusionItem *> *found, NSInteger unreadable,
                         void (^done)(NSArray<SGFusionItem *> *, NSInteger, NSInteger)) {
    NSString *url = [NSString stringWithFormat:@"%@/playlists/%@/%@?limit=100&offset=%lu", kAPI, playlist, shape, (unsigned long)offset];
    send(NO, @"GET", url, nil, kRetries, ^(NSInteger status, id json) {
        NSArray *entries = list(record(json)[@"items"]);
        if (!fine(status) || !entries) {
            // The older shape, once, before anything was read under the newer one.
            if (offset == 0 && [shape isEqualToString:@"items"] && status != kNoAnswer && status != 401 && status != 429) {
                webItemsPage(playlist, @"tracks", 0, found, unreadable, done);
                return;
            }
            done(nil, 0, fine(status) ? kNoItems : status);
            return;
        }
        NSInteger skipped = unreadable;
        for (id entry in entries) {
            NSDictionary *item = record(record(entry)[@"item"]) ?: record(record(entry)[@"track"]);
            NSString *uri = text(item[@"uri"]);
            // A file of the user's own, or an entry Spotify no longer has: nothing that can be added elsewhere.
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
        NSInteger total = count(record(json)[@"total"]);
        NSUInteger read = offset + entries.count;
        if (entries.count == 0 || (total >= 0 && (NSInteger)read >= total) || (total < 0 && entries.count < 100)) {
            if (total >= 0 && (NSInteger)read < total) done(nil, 0, kShort);
            else done(found, skipped, status);
            return;
        }
        webItemsPage(playlist, shape, read, found, skipped, done);
    });
}

// A playlist as Spotify's own endpoint gives it: `length` entries in all, `contents.items` the ones from
// `contents.pos` on, each with its uri, and `contents.truncated` when more follow.
static void innerItemsPage(NSString *playlist, NSUInteger from, NSMutableArray<SGFusionItem *> *found, NSInteger unreadable,
                           void (^done)(NSArray<SGFusionItem *> *, NSInteger, NSInteger)) {
    NSMutableString *path = [NSMutableString stringWithFormat:@"/playlist/v2/playlist/%@", escaped(playlist)];
    if (from) [path appendFormat:@"?from=%lu&length=%d", (unsigned long)from, kInnerPage];
    send(YES, @"GET", innerURL(path), nil, kRetries, ^(NSInteger status, id json) {
        NSDictionary *answer = record(json), *contents = record(answer[@"contents"]);
        NSInteger total = count(answer[@"length"]);
        // A playlist with nothing in it is written without its contents.
        if (!fine(status) || !answer || (!contents && total > 0)) {
            if (fine(status)) SGLog(@"fusion: a playlist answered with %@", [answer.allKeys componentsJoinedByString:@","] ?: @"no names");
            done(nil, 0, fine(status) ? kNoItems : status);
            return;
        }
        if (from && count(contents[@"pos"]) != (NSInteger)from) {
            SGLog(@"fusion: a playlist's window at %lu came back at %ld", (unsigned long)from, (long)count(contents[@"pos"]));
            done(nil, 0, kShort);
            return;
        }
        NSArray *entries = list(contents[@"items"]) ?: @[];
        NSInteger skipped = unreadable;
        for (id entry in entries) {
            NSString *uri = text(record(entry)[@"uri"]);
            if (!uri.length || [uri hasPrefix:@"spotify:local:"]) {
                skipped++;
                continue;
            }
            SGFusionItem *one = [SGFusionItem new];
            one.uri = uri;
            one.isTrack = [uri hasPrefix:@"spotify:track:"];
            [found addObject:one];
        }
        NSUInteger read = from + entries.count;
        if ([contents[@"truncated"] isEqual:@YES] && entries.count) {
            innerItemsPage(playlist, read, found, skipped, done);
            return;
        }
        if (total >= 0 && (NSInteger)read < total) done(nil, 0, kShort);
        else done(found, skipped, status);
    });
}

void SGFusionLoadItems(NSString *playlist, void (^done)(NSArray<SGFusionItem *> *, NSInteger, NSString *)) {
    void (^inner)(NSInteger) = ^(NSInteger web) {
        innerItemsPage(playlist, 0, [NSMutableArray array], 0, ^(NSArray<SGFusionItem *> *items, NSInteger unreadable, NSInteger status) {
            if (items) done(items, unreadable, nil);
            else done(nil, 0, both(web, status));
        });
    };
    if (sg_webShut || [sg_followed containsObject:playlist]) {
        inner(kUntried);
        return;
    }
    webItemsPage(playlist, @"items", 0, [NSMutableArray array], 0, ^(NSArray<SGFusionItem *> *items, NSInteger unreadable, NSInteger status) {
        if (items) done(items, unreadable, nil);
        else inner(status);
    });
}

#pragma mark - changes

static void webAdd(NSString *playlist, NSString *shape, NSArray<NSString *> *uris, NSUInteger from,
                   void (^progress)(NSUInteger), void (^done)(NSUInteger, NSInteger)) {
    if (from >= uris.count) {
        done(uris.count, 200);
        return;
    }
    NSArray<NSString *> *batch = [uris subarrayWithRange:NSMakeRange(from, MIN((NSUInteger)100, uris.count - from))];
    NSString *url = [NSString stringWithFormat:@"%@/playlists/%@/%@", kAPI, playlist, shape];
    send(NO, @"POST", url, @{@"uris": batch}, kRetries, ^(NSInteger status, id json) {
        if (!fine(status)) {
            if (from == 0 && [shape isEqualToString:@"items"] && (status == 404 || status == 405)) {
                webAdd(playlist, @"tracks", uris, from, progress, done);
                return;
            }
            done(from, status);
            return;
        }
        NSUInteger added = from + batch.count;
        if (progress) progress(added);
        webAdd(playlist, shape, uris, added, progress, done);
    });
}

// One list of operations for a /changes: what the web player posts, less what says who is posting.
static NSDictionary *changes(NSDictionary *operation) {
    return @{@"deltas": @[@{@"ops": @[operation]}], @"wantResultingRevisions": @NO, @"wantSyncResult": @NO, @"nonces": @[]};
}

static void innerAdd(NSString *playlist, NSArray<NSString *> *uris, NSUInteger from,
                     void (^progress)(NSUInteger), void (^done)(NSUInteger, NSInteger)) {
    if (from >= uris.count) {
        done(uris.count, 200);
        return;
    }
    NSArray<NSString *> *batch = [uris subarrayWithRange:NSMakeRange(from, MIN((NSUInteger)100, uris.count - from))];
    NSString *now = [NSString stringWithFormat:@"%lld", (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (NSString *uri in batch) [items addObject:@{@"uri": uri, @"attributes": @{@"timestamp": now}}];
    // kind 2: add, here at the end.
    NSDictionary *body = changes(@{@"kind": @2, @"add": @{@"items": items, @"addLast": @YES}});
    NSString *url = innerURL([NSString stringWithFormat:@"/playlist/v2/playlist/%@/changes", escaped(playlist)]);
    send(YES, @"POST", url, body, kRetries, ^(NSInteger status, id json) {
        if (!fine(status)) {
            done(from, status);
            return;
        }
        NSUInteger added = from + batch.count;
        if (progress) progress(added);
        innerAdd(playlist, uris, added, progress, done);
    });
}

void SGFusionAddItems(NSString *playlist, NSArray<NSString *> *uris, NSUInteger from,
                      void (^progress)(NSUInteger), void (^done)(NSUInteger, NSString *)) {
    void (^inner)(NSUInteger, NSInteger) = ^(NSUInteger start, NSInteger web) {
        innerAdd(playlist, uris, start, progress, ^(NSUInteger added, NSInteger status) {
            done(added, fine(status) ? nil : both(web, status));
        });
    };
    if (sg_webShut) {
        inner(from, kUntried);
        return;
    }
    webAdd(playlist, @"items", uris, from, progress, ^(NSUInteger added, NSInteger status) {
        if (fine(status)) done(added, nil);
        // Only a plain refusal goes on through the other door: with no answer the batch may have gone in.
        else if (status >= 400 && status < 500) inner(added, status);
        else done(added, explain(status));
    });
}

void SGFusionRemoveFromLibrary(NSString *playlist, void (^done)(NSString *)) {
    NSString *uri = [@"spotify:playlist:" stringByAppendingString:playlist];
    void (^inner)(NSInteger) = ^(NSInteger web) {
        NSString *user = account();
        if (!user.length) {
            done(web == kUntried ? explain(kNoAccount) : explain(web));
            return;
        }
        // kind 3: remove, the entry told by its uri.
        NSDictionary *body = changes(@{@"kind": @3, @"rem": @{@"items": @[@{@"uri": uri}], @"itemsAsKey": @YES}});
        NSString *url = innerURL([NSString stringWithFormat:@"/playlist/v2/user/%@/rootlist/changes", escaped(user)]);
        send(YES, @"POST", url, body, kRetries, ^(NSInteger status, id json) {
            done(fine(status) ? nil : both(web, status));
        });
    };
    if (sg_webShut) {
        inner(kUntried);
        return;
    }
    NSString *query = [uri stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    send(NO, @"DELETE", [NSString stringWithFormat:@"%@/me/library?uris=%@", kAPI, query], nil, kRetries, ^(NSInteger status, id json) {
        if (fine(status)) {
            done(nil);
            return;
        }
        send(NO, @"DELETE", [NSString stringWithFormat:@"%@/playlists/%@/followers", kAPI, playlist], nil, kRetries, ^(NSInteger older, id reply) {
            if (fine(older)) done(nil);
            else inner(older ?: status);
        });
    });
}
