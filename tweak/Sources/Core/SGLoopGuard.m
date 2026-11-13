#import <CoreFoundation/CoreFoundation.h>
#import "SGLog.h"
#import "SGLoopGuard.h"

static const NSUInteger kMost = 400;
static NSUInteger sg_turn = 1;

static NSMutableDictionary<NSString *, NSNumber *> *sg_notes;
static NSUInteger sg_notesTurn;

static void turned(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    sg_turn++;
}

void SGLoopNote(const char *what) {
    if (!sg_notes) sg_notes = [NSMutableDictionary dictionary];
    if (sg_notesTurn != sg_turn) {
        [sg_notes removeAllObjects];
        sg_notesTurn = sg_turn;
    }
    NSString *key = @(what);
    sg_notes[key] = @(sg_notes[key].unsignedIntegerValue + 1);
}

BOOL SGLoopGuard(const char *name) {
    static NSMutableDictionary<NSString *, NSNumber *> *counts, *turns;
    static NSMutableSet<NSString *> *told;
    if (!counts) {
        counts = [NSMutableDictionary dictionary];
        turns = [NSMutableDictionary dictionary];
        told = [NSMutableSet set];
        CFRunLoopObserverRef observer = CFRunLoopObserverCreate(NULL, kCFRunLoopBeforeWaiting | kCFRunLoopAfterWaiting, true, 0, turned, NULL);
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, kCFRunLoopCommonModes);
    }
    NSString *key = @(name);
    NSUInteger count = turns[key].unsignedIntegerValue == sg_turn ? counts[key].unsignedIntegerValue + 1 : 1;
    counts[key] = @(count);
    turns[key] = @(sg_turn);
    if (count <= kMost) return NO;
    if (![told containsObject:key]) {
        [told addObject:key];
        NSMutableArray<NSString *> *changes = [NSMutableArray array];
        if (sg_notesTurn == sg_turn) {
            for (NSString *what in [sg_notes keysSortedByValueUsingSelector:@selector(compare:)].reverseObjectEnumerator) {
                [changes addObject:[NSString stringWithFormat:@"%@ %@", what, sg_notes[what]]];
            }
        }
        SGLog(@"loop guard: %@ ran %lu times in one turn of the run loop, stopped for that turn; the mod changed: %@", key,
              (unsigned long)count, changes.count ? [changes componentsJoinedByString:@", "] : @"nothing it notes");
    }
    return YES;
}
