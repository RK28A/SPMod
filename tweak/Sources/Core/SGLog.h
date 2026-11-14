#import <Foundation/Foundation.h>
#import <os/log.h>

void SGLogMessage(NSString *message);
#define SGLog(fmt, ...) SGLogMessage([NSString stringWithFormat:(fmt), ##__VA_ARGS__])

// Debug lines (Developer → Debug logs, on unless switched off, read once a launch): what each module did
// first, so a log says which parts ran. SGDebugOnce says it the first time only, costing one test after.
#define SGKeyDebugLogs @"spotifyglass.debug.logs"
BOOL SGDebugOn(void);
#define SGDebug(fmt, ...) do { if (SGDebugOn()) SGLogMessage([@"debug: " stringByAppendingString:[NSString stringWithFormat:(fmt), ##__VA_ARGS__]]); } while (0)
#define SGDebugOnce(fmt, ...) do { static BOOL sg_said_; if (!sg_said_) { sg_said_ = YES; SGDebug(fmt, ##__VA_ARGS__); } } while (0)

// Long dumps, split into numbered parts under the unified log's size cap.
void SGLogLong(NSString *tag, NSString *text);
NSString *SGLogContents(void);
// Logs every class of the list that this Spotify does not have; a feature calls it from its %ctor.
void SGRequireClasses(NSArray<NSString *> *names);
