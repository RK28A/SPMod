// How the launch before this one ended, said in the log at launch (the log itself is kept across launches,
// SGLog.m). A crash writes its signal or exception and the stack to a file of its own, from the handler,
// which the next launch reads into the log. A launch that left neither that nor a clean exit was ended from
// outside: iOS took the app while it was in the background (memory, CPU) or it was swiped away; which state
// it was in is kept in a second small file. Memory warnings are logged as they come, since they are what
// comes before iOS takes an app for memory. Spotify's own handlers still run after these.
#import <UIKit/UIKit.h>
#import <execinfo.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import "Core/SGCore.h"

static int sg_crashFile = -1;
static const int kSignals[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP};
enum { kSignalCount = sizeof(kSignals) / sizeof(kSignals[0]) };
static struct sigaction sg_before[kSignalCount];
static NSUncaughtExceptionHandler *sg_exceptionBefore;

static NSURL *fileNamed(NSString *name) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [support URLByAppendingPathComponent:@"spoti.pw" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder URLByAppendingPathComponent:name];
}

static void put(const char *text) {
    if (sg_crashFile >= 0 && text) write(sg_crashFile, text, strlen(text));
}

static void putStack(void) {
    void *frames[64];
    int count = backtrace(frames, 64);
    if (sg_crashFile >= 0 && count > 0) backtrace_symbols_fd(frames, count, sg_crashFile);
}

static void onSignal(int number, siginfo_t *info, void *context) {
    char line[48] = "signal 00\n";
    line[7] = (char)('0' + (number / 10) % 10);
    line[8] = (char)('0' + number % 10);
    put(line);
    putStack();
    for (int i = 0; i < kSignalCount; i++) {
        if (kSignals[i] != number) continue;
        sigaction(number, &sg_before[i], NULL);
        break;
    }
    raise(number);
}

static void onException(NSException *exception) {
    put("exception ");
    put(exception.name.UTF8String);
    put(": ");
    put(exception.reason.UTF8String);
    put("\n");
    put([exception.callStackSymbols componentsJoinedByString:@"\n"].UTF8String);
    put("\n");
    if (sg_exceptionBefore) sg_exceptionBefore(exception);
}

static void setState(NSString *state) {
    [[state dataUsingEncoding:NSUTF8StringEncoding] writeToURL:fileNamed(@"run-state") atomically:YES];
}

%ctor {
    NSURL *crash = fileNamed(@"last-crash.txt");
    NSString *recorded = [NSString stringWithContentsOfURL:crash encoding:NSUTF8StringEncoding error:nil];
    NSString *state = [NSString stringWithContentsOfURL:fileNamed(@"run-state") encoding:NSUTF8StringEncoding error:nil];
    if (recorded.length) {
        SGLogLong(@"last launch: crashed", recorded.length > 6000 ? [recorded substringToIndex:6000] : recorded);
    } else if ([state isEqualToString:@"terminated"]) {
        SGLog(@"last launch: ended cleanly");
    } else if (state.length) {
        SGLog(@"last launch: ended with no crash recorded while in the %@: taken by iOS (memory or CPU) or swiped away", state);
    }
    sg_crashFile = open(crash.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    setState(@"foreground");

    sg_exceptionBefore = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(onException);
    // After Spotify has put its own handlers up, so they are the ones kept and handed the signal on.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSUncaughtExceptionHandler *now = NSGetUncaughtExceptionHandler();
        if (now != onException) {
            sg_exceptionBefore = now;
            NSSetUncaughtExceptionHandler(onException);
        }
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_sigaction = onSignal;
        action.sa_flags = SA_SIGINFO;
        sigemptyset(&action.sa_mask);
        for (int i = 0; i < kSignalCount; i++) sigaction(kSignals[i], &action, &sg_before[i]);
    });

    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) { setState(@"background"); }];
    [center addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification *note) { setState(@"foreground"); }];
    [center addObserverForName:UIApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *note) { setState(@"terminated"); }];
    [center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        SGLog(@"memory warning from iOS, in the %@", UIApplication.sharedApplication.applicationState == UIApplicationStateBackground ? @"background" : @"foreground");
    }];
}
