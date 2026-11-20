// Developer > Phone & app stats: what the app uses and what the phone is doing, read live (the page's values
// are read again every second while it is on screen, SGModPage's ticker). Folder sizes walk the disk, so
// they are worked out off the main thread at most every 30 s and shown from that.
#import <UIKit/UIKit.h>
#import <mach/mach.h>
#import <os/proc.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "DeviceStats.h"

static CFAbsoluteTime sg_started;

__attribute__((constructor)) static void noteStart(void) {
    sg_started = CFAbsoluteTimeGetCurrent();
}

static NSString *bytesText(double bytes) {
    return [NSByteCountFormatter stringFromByteCount:(long long)bytes countStyle:NSByteCountFormatterCountStyleMemory];
}

static NSString *durationText(NSTimeInterval seconds) {
    long s = (long)seconds;
    if (s >= 86400) return [NSString stringWithFormat:@"%ldd %ldh %02ldm", s / 86400, s % 86400 / 3600, s % 3600 / 60];
    if (s >= 3600) return [NSString stringWithFormat:@"%ldh %02ldm", s / 3600, s % 3600 / 60];
    return [NSString stringWithFormat:@"%ldm %02lds", s / 60, s % 60];
}

#pragma mark - the app

static BOOL vmInfo(task_vm_info_data_t *info) {
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    return task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)info, &count) == KERN_SUCCESS;
}

static NSString *memoryUsed(void) {
    task_vm_info_data_t info;
    return vmInfo(&info) ? bytesText(info.phys_footprint) : @"?";
}

static NSString *memoryPeak(void) {
    task_vm_info_data_t info;
    return vmInfo(&info) && info.ledger_phys_footprint_peak > 0 ? bytesText(info.ledger_phys_footprint_peak) : @"?";
}

static NSString *memoryLeft(void) {
    size_t left = os_proc_available_memory();
    return left ? bytesText(left) : @"?";
}

// The app's CPU across its threads (100% is one core), and how many threads it runs.
static void threads(double *cpu, unsigned *count) {
    thread_act_array_t list;
    mach_msg_type_number_t number = 0;
    *cpu = 0;
    *count = 0;
    if (task_threads(mach_task_self(), &list, &number) != KERN_SUCCESS) return;
    for (mach_msg_type_number_t i = 0; i < number; i++) {
        thread_basic_info_data_t info;
        mach_msg_type_number_t size = THREAD_BASIC_INFO_COUNT;
        if (thread_info(list[i], THREAD_BASIC_INFO, (thread_info_t)&info, &size) == KERN_SUCCESS && !(info.flags & TH_FLAGS_IDLE))
            *cpu += info.cpu_usage / (double)TH_USAGE_SCALE * 100;
        mach_port_deallocate(mach_task_self(), list[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)list, number * sizeof(thread_act_t));
    *count = number;
}

static NSString *cpuText(void) {
    double cpu;
    unsigned count;
    threads(&cpu, &count);
    return [NSString stringWithFormat:@"%.0f%%", cpu];
}

static NSString *threadText(void) {
    double cpu;
    unsigned count;
    threads(&cpu, &count);
    return [NSString stringWithFormat:@"%u", count];
}

static NSString *cpuTime(void) {
    struct task_thread_times_info times;
    mach_msg_type_number_t count = TASK_THREAD_TIMES_INFO_COUNT;
    struct mach_task_basic_info basic;
    mach_msg_type_number_t basicCount = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_THREAD_TIMES_INFO, (task_info_t)&times, &count) != KERN_SUCCESS ||
        task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&basic, &basicCount) != KERN_SUCCESS) return @"?";
    double seconds = times.user_time.seconds + times.system_time.seconds + basic.user_time.seconds + basic.system_time.seconds
        + (times.user_time.microseconds + times.system_time.microseconds + basic.user_time.microseconds + basic.system_time.microseconds) / 1e6;
    return [NSString stringWithFormat:@"%.0f s", seconds];
}

#pragma mark - folders, worked out in the background

static NSDictionary<NSString *, NSNumber *> *sg_sizes;
static CFAbsoluteTime sg_sizedAt;
static BOOL sg_sizing;

static unsigned long long folderSize(NSURL *folder) {
    unsigned long long total = 0;
    NSDirectoryEnumerator *walk = [NSFileManager.defaultManager enumeratorAtURL:folder
        includingPropertiesForKeys:@[NSURLTotalFileAllocatedSizeKey, NSURLIsRegularFileKey] options:0 errorHandler:nil];
    for (NSURL *file in walk) {
        NSNumber *regular = nil, *size = nil;
        [file getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
        if (!regular.boolValue) continue;
        [file getResourceValue:&size forKey:NSURLTotalFileAllocatedSizeKey error:nil];
        total += size.unsignedLongLongValue;
    }
    return total;
}

static NSString *sizeOf(NSString *name) {
    if (!sg_sizing && CFAbsoluteTimeGetCurrent() - sg_sizedAt > 30) {
        sg_sizing = YES;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSFileManager *files = NSFileManager.defaultManager;
            NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory()];
            NSURL *library = [files URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *caches = [files URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
            NSURL *documents = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
            unsigned long long all = folderSize(home), cached = folderSize(caches), docs = folderSize(documents);
            unsigned long long temporary = folderSize([NSURL fileURLWithPath:NSTemporaryDirectory()]);
            unsigned long long app = folderSize(NSBundle.mainBundle.bundleURL);
            unsigned long long rest = folderSize(library);
            NSDictionary *sizes = @{@"all": @(all), @"caches": @(cached), @"documents": @(docs), @"tmp": @(temporary),
                                    @"bundle": @(app), @"library": @(rest)};
            dispatch_async(dispatch_get_main_queue(), ^{
                sg_sizes = sizes;
                sg_sizedAt = CFAbsoluteTimeGetCurrent();
                sg_sizing = NO;
            });
        });
    }
    NSNumber *size = sg_sizes[name];
    return size ? bytesText(size.doubleValue) : @"Measuring…";
}

#pragma mark - the phone

static NSString *machine(void) {
    struct utsname name;
    uname(&name);
    return [NSString stringWithUTF8String:name.machine] ?: @"?";
}

static NSString *thermalText(void) {
    switch (NSProcessInfo.processInfo.thermalState) {
        case NSProcessInfoThermalStateNominal: return @"Normal";
        case NSProcessInfoThermalStateFair: return @"Warm";
        case NSProcessInfoThermalStateSerious: return @"Hot (motion rests)";
        case NSProcessInfoThermalStateCritical: return @"Critical";
    }
    return @"?";
}

static NSString *batteryText(void) {
    UIDevice *device = UIDevice.currentDevice;
    device.batteryMonitoringEnabled = YES;
    float level = device.batteryLevel;
    NSString *state = @{@(UIDeviceBatteryStateCharging): @"charging", @(UIDeviceBatteryStateFull): @"full",
                        @(UIDeviceBatteryStateUnplugged): @"on battery"}[@(device.batteryState)] ?: @"unknown";
    return level < 0 ? state : [NSString stringWithFormat:@"%.0f%%, %@", level * 100, state];
}

static NSString *diskText(BOOL free) {
    NSDictionary *values = [[NSURL fileURLWithPath:NSHomeDirectory()] resourceValuesForKeys:
        @[NSURLVolumeAvailableCapacityForImportantUsageKey, NSURLVolumeTotalCapacityKey] error:nil];
    NSNumber *number = values[free ? NSURLVolumeAvailableCapacityForImportantUsageKey : NSURLVolumeTotalCapacityKey];
    return number ? bytesText(number.doubleValue) : @"?";
}

static NSString *screenText(void) {
    UIScreen *screen = UIScreen.mainScreen;
    return [NSString stringWithFormat:@"%.0f × %.0f pt, @%.0fx, up to %ld Hz", screen.bounds.size.width, screen.bounds.size.height,
            screen.scale, (long)screen.maximumFramesPerSecond];
}

static NSString *loadText(void) {
    double load[3];
    if (getloadavg(load, 3) < 0) return @"?";
    return [NSString stringWithFormat:@"%.2f  %.2f  %.2f", load[0], load[1], load[2]];
}

static SGModRow *stat(NSString *title, NSString *symbol, NSString *(^value)(void)) {
    return SGWithSymbol(SGStatRow(title, value), symbol);
}

UIViewController *SGDeviceStatsPage(void) {
    NSProcessInfo *process = NSProcessInfo.processInfo;
    NSBundle *bundle = NSBundle.mainBundle;
    SGModSection *app = SGNotedSection(@"The app", @[
        stat(@"Memory used", @"memorychip", ^NSString *{ return memoryUsed(); }),
        stat(@"Memory peak", @"chart.line.uptrend.xyaxis", ^NSString *{ return memoryPeak(); }),
        stat(@"Memory left before iOS stops it", @"gauge.with.dots.needle.33percent", ^NSString *{ return memoryLeft(); }),
        stat(@"CPU now", @"cpu", ^NSString *{ return cpuText(); }),
        stat(@"CPU time since launch", @"timer", ^NSString *{ return cpuTime(); }),
        stat(@"Threads", @"line.3.horizontal", ^NSString *{ return threadText(); }),
        stat(@"Open for", @"clock", ^NSString *{ return durationText(CFAbsoluteTimeGetCurrent() - sg_started); }),
        stat(@"In the background", @"moon", ^NSString *{ return SGAppInBackground() ? @"Yes" : @"No"; }),
    ], @"CPU: 100% is one core fully busy. Memory: what iOS counts against the app (its footprint).");

    SGModSection *storage = SGNotedSection(@"Storage", @[
        stat(@"All the app's data", @"externaldrive", ^NSString *{ return sizeOf(@"all"); }),
        stat(@"Caches", @"tray.full", ^NSString *{ return sizeOf(@"caches"); }),
        stat(@"Library", @"books.vertical", ^NSString *{ return sizeOf(@"library"); }),
        stat(@"Documents", @"doc", ^NSString *{ return sizeOf(@"documents"); }),
        stat(@"Temporary files", @"clock.arrow.circlepath", ^NSString *{ return sizeOf(@"tmp"); }),
        stat(@"The app itself", @"app", ^NSString *{ return sizeOf(@"bundle"); }),
        stat(@"Free on the phone", @"internaldrive", ^NSString *{ return diskText(YES); }),
        stat(@"Phone capacity", @"internaldrive.fill", ^NSString *{ return diskText(NO); }),
    ], @"Folder sizes are measured again every 30 seconds.");

    SGModSection *phone = SGSection(@"The phone", @[
        stat(@"Temperature", @"thermometer.medium", ^NSString *{ return thermalText(); }),
        stat(@"Battery", @"battery.75percent", ^NSString *{ return batteryText(); }),
        stat(@"Low Power Mode", @"bolt.badge.automatic", ^NSString *{ return NSProcessInfo.processInfo.lowPowerModeEnabled ? @"On" : @"Off"; }),
        stat(@"System load (1, 5, 15 min)", @"waveform.path.ecg", ^NSString *{ return loadText(); }),
        stat(@"Memory (RAM)", @"memorychip.fill", ^NSString *{ return bytesText(process.physicalMemory); }),
        stat(@"CPU cores", @"cpu.fill", ^NSString *{ return [NSString stringWithFormat:@"%lu active of %lu", (unsigned long)process.activeProcessorCount, (unsigned long)process.processorCount]; }),
        stat(@"On since", @"power", ^NSString *{ return durationText(process.systemUptime); }),
        stat(@"Screen", @"iphone", ^NSString *{ return screenText(); }),
        stat(@"Brightness", @"sun.max", ^NSString *{ return [NSString stringWithFormat:@"%.0f%%", UIScreen.mainScreen.brightness * 100]; }),
        stat(@"Model", @"iphone.gen3", ^NSString *{ return machine(); }),
        stat(@"iOS", @"apple.logo", ^NSString *{ return [NSString stringWithFormat:@"%@ (%@)", UIDevice.currentDevice.systemVersion, process.operatingSystemVersionString]; }),
        stat(@"Region and language", @"globe", ^NSString *{ return [NSString stringWithFormat:@"%@, %@", NSLocale.currentLocale.localeIdentifier, NSLocale.preferredLanguages.firstObject ?: @"?"]; }),
        stat(@"Time zone", @"clock.badge", ^NSString *{ return NSTimeZone.localTimeZone.name; }),
    ]);

    SGModSection *versions = SGSection(@"Versions", @[
        stat(@"Spotify", @"music.note", ^NSString *{
            return [NSString stringWithFormat:@"%@ (%@)", [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
                    [bundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?"];
        }),
        stat(@"SPMod", @"sparkles", ^NSString *{ return @SG_VERSION; }),
        stat(@"Look", @"paintpalette", ^NSString *{ return SGRedesignedUI() ? @"Redesigned" : @"Native"; }),
        stat(@"Bundle", @"shippingbox", ^NSString *{ return bundle.bundleIdentifier ?: @"?"; }),
    ]);

    return [[SGModPage alloc] initWithTitle:@"Phone & app stats" intro:nil sections:@[app, storage, phone, versions] footer:nil];
}
