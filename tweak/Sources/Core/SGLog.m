#import "SGLog.h"

static const NSUInteger kLogLimit = 2 * 1024 * 1024;
static dispatch_queue_t sg_logQueue;
static const void *sg_logQueueKey = &sg_logQueueKey;

static dispatch_queue_t logQueue(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_logQueue = dispatch_queue_create("spotifyglass.diagnostics.log", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(sg_logQueue, sg_logQueueKey, (void *)sg_logQueueKey, NULL);
    });
    return sg_logQueue;
}

static NSURL *logFile(void) {
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                          inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"spoti.pw" isDirectory:YES]
            URLByAppendingPathComponent:@"diagnostics.log"];
}

// The launch before this one, whole: its log is set aside as this launch writes its first line, and the one
// set aside before it goes. Two launches are kept, this one and the last.
static NSURL *previousLogFile(void) {
    return [logFile().URLByDeletingLastPathComponent URLByAppendingPathComponent:@"diagnostics.previous.log"];
}

static void turnLogOver(void) {
    static BOOL turned;
    if (turned) return;
    turned = YES;
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files fileExistsAtPath:logFile().path]) return;
    [files removeItemAtURL:previousLogFile() error:nil];
    [files moveItemAtURL:logFile() toURL:previousLogFile() error:nil];
}

// The file stays open and its size is kept here: a line is one write, nothing more. Past the limit the file is
// cut once to its newer half (not on every line, which rewrote two megabytes each time).
static NSFileHandle *sg_handle;
static unsigned long long sg_size;

static BOOL openLog(void) {
    if (sg_handle) return YES;
    NSURL *url = logFile();
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:url.URLByDeletingLastPathComponent
                               withIntermediateDirectories:YES attributes:nil error:&error]) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, "[spotifyglass] cannot create diagnostics directory: %{public}s",
                         error.localizedDescription.UTF8String ?: "unknown error");
        return NO;
    }
    if (![NSFileManager.defaultManager fileExistsAtPath:url.path] &&
        ![NSFileManager.defaultManager createFileAtPath:url.path contents:nil attributes:nil]) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, "[spotifyglass] cannot create diagnostics log");
        return NO;
    }
    sg_handle = [NSFileHandle fileHandleForWritingAtPath:url.path];
    if (!sg_handle) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, "[spotifyglass] cannot open diagnostics log");
        return NO;
    }
    sg_size = [sg_handle seekToEndOfFile];
    return YES;
}

static void cutLog(void) {
    [sg_handle closeFile];
    sg_handle = nil;
    NSURL *url = logFile();
    NSMutableData *data = [[NSData dataWithContentsOfURL:url options:0 error:nil] mutableCopy];
    if (data.length > kLogLimit / 2) {
        NSUInteger discard = data.length - kLogLimit / 2;
        const uint8_t *bytes = data.bytes;
        while (discard < data.length && bytes[discard] != '\n') discard++;
        if (discard < data.length) discard++;
        [data replaceBytesInRange:NSMakeRange(0, discard) withBytes:NULL length:0];
        [data writeToURL:url options:NSDataWritingAtomic error:nil];
    }
    openLog();
}

static void appendLog(NSString *message) {
    turnLogOver();
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }
    NSString *line = [NSString stringWithFormat:@"%@ [spotifyglass] %@\n", [formatter stringFromDate:NSDate.date], message];
    NSData *addition = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!openLog()) return;
    if (sg_size + addition.length > kLogLimit) cutLog();
    if (!sg_handle) return;
    NSError *error = nil;
    if (![sg_handle writeData:addition error:&error]) {
        os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, "[spotifyglass] cannot append diagnostics log: %{public}s",
                         error.localizedDescription.UTF8String ?: "unknown error");
        [sg_handle closeFile];
        sg_handle = nil;
        return;
    }
    sg_size += addition.length;
}

BOOL SGDebugOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        id stored = [NSUserDefaults.standardUserDefaults objectForKey:SGKeyDebugLogs];
        on = stored ? [stored boolValue] : YES;
    });
    return on;
}

void SGLogMessage(NSString *message) {
    NSString *text = message ?: @"(empty log message)";
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[spotifyglass] %{public}s", text.UTF8String);
    dispatch_async(logQueue(), ^{ appendLog(text); });
}

NSString *SGLogContents(void) {
    __block NSString *contents;
    dispatch_block_t read = ^{
        NSError *error = nil;
        turnLogOver();
        contents = [NSString stringWithContentsOfURL:logFile() encoding:NSUTF8StringEncoding error:&error];
        NSString *before = [NSString stringWithContentsOfURL:previousLogFile() encoding:NSUTF8StringEncoding error:nil];
        if (before.length) {
            contents = [NSString stringWithFormat:@"===== the launch before this one =====\n%@\n===== this launch =====\n%@", before, contents ?: @""];
        }
        if (!contents && error && error.code != NSFileReadNoSuchFileError) {
            os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_ERROR, "[spotifyglass] cannot read diagnostics log: %{public}s",
                             error.localizedDescription.UTF8String ?: "unknown error");
            contents = [NSString stringWithFormat:@"Could not read the diagnostics log: %@", error.localizedDescription];
        }
        if (!contents) contents = @"No diagnostics have been recorded yet.";
    };
    dispatch_queue_t queue = logQueue();
    if (dispatch_get_specific(sg_logQueueKey)) read();
    else dispatch_sync(queue, read);
    return contents;
}

// The unified log cuts a message at about 1 KB, so long dumps go out as numbered parts.
void SGLogLong(NSString *tag, NSString *text) {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSMutableString *current = [NSMutableString string];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (current.length && [current lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 900) {
            [parts addObject:[current copy]];
            [current setString:@""];
        }
        [current appendFormat:@"%@\n", line];
    }
    if (current.length) [parts addObject:current];
    [parts enumerateObjectsUsingBlock:^(NSString *part, NSUInteger i, BOOL *stop) {
        SGLog(@"%@ %lu/%lu\n%@", tag, (unsigned long)i + 1, (unsigned long)parts.count, part);
    }];
}

void SGRequireClasses(NSArray<NSString *> *names) {
    for (NSString *name in names) {
        if (!NSClassFromString(name)) SGLog(@"class %@ not found, its hooks are inactive", name);
    }
}
