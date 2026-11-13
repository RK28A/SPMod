// SGFreezeClip.h says what these are. The writers end as SGMotionClip.m's do: beside the file, then moved
// over it once whole, with the encoder's waits bounded (SGVideoEncodeSafety.h).
#import <AVFoundation/AVFoundation.h>
#import "SGFreezeClip.h"
#import "SGVideoEncodeSafety.h"

static const int32_t kStillSeconds = 2, kStillFPS = 2;
static const NSTimeInterval kLoadWait = 30;

static AVAssetTrack *videoTrack(AVURLAsset *asset) {
    __block AVAssetTrack *track = nil;
    dispatch_semaphore_t loaded = dispatch_semaphore_create(0);
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *error) {
        track = tracks.firstObject;
        dispatch_semaphore_signal(loaded);
    }];
    if (dispatch_semaphore_wait(loaded, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLoadWait * NSEC_PER_SEC))) != 0) {
        [asset cancelLoading];
        return nil;
    }
    return track;
}

static double lengthOf(AVAssetTrack *track) {
    double length = track ? CMTimeGetSeconds(track.timeRange.duration) : 0;
    return isfinite(length) && length > 0 ? length : 0;
}

CGImageRef SGFreezeClipFrame(NSURL *file, double at, double *length, double *where) {
    if (length) *length = 0;
    if (where) *where = 0;
    if (!file) return NULL;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    double whole = lengthOf(videoTrack(asset));
    if (whole <= 0) return NULL;
    double landed = isfinite(at) && at > 0 ? fmod(at, whole) : 0;
    // The last frame's own time is short of the length: asked for at the very end, nothing comes back.
    if (landed > whole - 0.05) landed = 0;
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.05, 600);
    generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.05, 600);
    __block CGImageRef frame = NULL;
    dispatch_semaphore_t made = dispatch_semaphore_create(0);
    [generator generateCGImageAsynchronouslyForTime:CMTimeMakeWithSeconds(landed, 600)
                                  completionHandler:^(CGImageRef image, CMTime actual, NSError *error) {
        if (image) frame = CGImageRetain(image);
        dispatch_semaphore_signal(made);
    }];
    if (dispatch_semaphore_wait(made, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLoadWait * NSEC_PER_SEC))) != 0) {
        [generator cancelAllCGImageGeneration];
        return NULL;
    }
    if (!frame) return NULL;
    if (length) *length = whole;
    if (where) *where = landed;
    return frame;
}

BOOL SGFreezeClipWriteStill(NSURL *file, CGImageRef frame) {
    if (!file || !frame) return NO;
    // H.264 takes even sides.
    size_t width = CGImageGetWidth(frame) / 2 * 2, height = CGImageGetHeight(frame) / 2 * 2;
    if (width < 2 || height < 2 || width > 4096 || height > 4096) return NO;
    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(width),
        AVVideoHeightKey: @(height),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(width * height * 3)},
    }];
    AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
        assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferWidthKey: @(width),
            (id)kCVPixelBufferHeightKey: @(height),
        }];
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];

    CVPixelBufferRef buffer = NULL;
    BOOL ok = adaptor.pixelBufferPool && CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer) == kCVReturnSuccess;
    if (ok && CVPixelBufferLockBaseAddress(buffer, 0) == kCVReturnSuccess) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef context = space ? CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), width, height, 8,
            CVPixelBufferGetBytesPerRow(buffer), space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little) : NULL;
        if (space) CGColorSpaceRelease(space);
        ok = context != NULL;
        if (context) {
            CGContextDrawImage(context, CGRectMake(0, 0, width, height), frame);
            CGContextRelease(context);
        }
        CVPixelBufferUnlockBaseAddress(buffer, 0);
    } else {
        ok = NO;
    }
    for (int32_t i = 0; i < kStillSeconds * kStillFPS && ok; i++) {
        ok = SGVideoReady(input, writer) && [adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i, kStillFPS)];
    }
    if (buffer) CVPixelBufferRelease(buffer);
    if (!ok) {
        [writer cancelWriting];
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMake(kStillSeconds, 1)];
    if (!SGVideoFinish(writer)) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}

BOOL SGFreezeClipWriteFrom(NSURL *clip, double from, NSURL *file) {
    if (!clip || !file) return NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:clip options:nil];
    AVAssetTrack *track = videoTrack(asset);
    double length = lengthOf(track);
    if (length <= 0 || !isfinite(from) || from <= 0 || from >= length) return NO;
    CGSize stored = track.naturalSize;
    if (!isfinite(stored.width) || !isfinite(stored.height) || stored.width < 2 || stored.height < 2 ||
        stored.width > 4096 || stored.height > 4096) return NO;

    NSURL *partial = [file URLByAppendingPathExtension:@"partial"];
    [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
    AVAssetWriter *writer = [AVAssetWriter assetWriterWithURL:partial fileType:AVFileTypeMPEG4 error:nil];
    AVAssetWriterInput *input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(floor(stored.width / 2) * 2),
        AVVideoHeightKey: @(floor(stored.height / 2) * 2),
        AVVideoCompressionPropertiesKey: @{AVVideoAverageBitRateKey: @(stored.width * stored.height * 3)},
    }];
    // Stood up the way the clip is, as SGMotionClip.m carries the turn over.
    input.transform = track.preferredTransform;
    if (!writer || ![writer canAddInput:input]) return NO;
    [writer addInput:input];
    if (![writer startWriting]) return NO;
    [writer startSessionAtSourceTime:kCMTimeZero];

    int32_t scale = 600;
    // The end of the clip first, then its start: each part read with its own reader, its frames given the
    // times they have in the turned clip, and one that would not come after the last written is left out.
    double parts[2][2] = {{from, length - from}, {0, from}};
    double last = -1;
    BOOL ok = YES;
    for (int part = 0; part < 2 && ok; part++) {
        double at = parts[part][0], take = parts[part][1], shift = part == 0 ? -from : length - from;
        AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
        AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        }];
        if (!reader || ![reader canAddOutput:output]) {
            ok = NO;
            break;
        }
        [reader addOutput:output];
        reader.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(at, scale), CMTimeMakeWithSeconds(take, scale));
        if (![reader startReading]) {
            ok = NO;
            break;
        }
        CMSampleBufferRef sample;
        while (ok && (sample = [output copyNextSampleBuffer])) {
            @autoreleasepool {
                double time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)) + shift;
                CMSampleBufferRef timed = NULL;
                CMSampleTimingInfo timing = {kCMTimeInvalid, CMTimeMakeWithSeconds(MAX(time, 0), scale), kCMTimeInvalid};
                BOOL keep = isfinite(time) && time > last + 0.001 && time < length && CMSampleBufferGetImageBuffer(sample)
                    && CMSampleBufferCreateCopyWithNewTiming(NULL, sample, 1, &timing, &timed) == noErr;
                CFRelease(sample);
                if (keep) {
                    last = MAX(time, 0);
                    ok = SGVideoReady(input, writer) && [input appendSampleBuffer:timed];
                }
                if (timed) CFRelease(timed);
            }
        }
        if (ok && reader.status != AVAssetReaderStatusCompleted) ok = NO;
        if (!ok) [reader cancelReading];
    }
    if (!ok || last < 0) {
        [writer cancelWriting];
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [input markAsFinished];
    [writer endSessionAtSourceTime:CMTimeMakeWithSeconds(length, scale)];
    if (!SGVideoFinish(writer)) {
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        return NO;
    }
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    return [NSFileManager.defaultManager moveItemAtURL:partial toURL:file error:nil];
}
