#import <CoreFoundation/CoreFoundation.h>
#import "SGLog.h"
#import "SGLoopGuard.h"

static const NSUInteger kMost = 400;
static NSUInteger sg_turn = 1;

static void turned(CFRunLoopObserverRef observer, CFRunLoopActivity activity, void *info) {
    sg_turn++;
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
        SGLog(@"loop guard: %@ ran %lu times in one turn of the run loop, stopped for that turn", key, (unsigned long)count);
    }
    return YES;
}
