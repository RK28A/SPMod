// Shared time limits for software-generated video clips. Must only run off the main thread.
// A suspended/failed encoder must not strand a rendering queue indefinitely.
#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static inline BOOL SGVideoReady(AVAssetWriterInput *input, AVAssetWriter *writer) {
    if (!input || !writer) return NO;
    NSTimeInterval start = NSProcessInfo.processInfo.systemUptime;
    while (writer.status == AVAssetWriterStatusWriting && !input.readyForMoreMediaData) {
        if (NSProcessInfo.processInfo.systemUptime - start > 30.0) return NO;
        [NSThread sleepForTimeInterval:0.005];
    }
    return writer.status == AVAssetWriterStatusWriting;
}

static inline BOOL SGVideoFinish(AVAssetWriter *writer) {
    if (!writer) return NO;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC))) != 0) {
        [writer cancelWriting];
        return NO;
    }
    return writer.status == AVAssetWriterStatusCompleted;
}
