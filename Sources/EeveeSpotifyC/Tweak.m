#import <Orion/Orion.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static IMP spmodOriginalMotionEnded = NULL;
static id (*spmodOriginalAssetInit)(id, SEL, NSURL *, NSDictionary *) = NULL;

static void spmod_motionEnded(id self, SEL _cmd, UIEventSubtype motion, UIEvent *event) {
    if (motion == UIEventSubtypeMotionShake) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"SPModDeviceShaken" object:nil];
    }
    if (spmodOriginalMotionEnded) {
        ((void (*)(id, SEL, UIEventSubtype, UIEvent *))spmodOriginalMotionEnded)(self, _cmd, motion, event);
    }
}

static id spmod_assetInit(id self, SEL _cmd, NSURL *url, NSDictionary *options) {
    if ([url isKindOfClass:[NSURL class]]) {
        NSString *absolute = [url.absoluteString lowercaseString];
        if ([absolute containsString:@"canvaz"]) {
            url = [NSURL fileURLWithPath:@"/dev/null/spmod-canvas-disabled.mp4"];
        }
    }
    return spmodOriginalAssetInit(self, _cmd, url, options);
}

static void spmod_installShakeHook(void) {
    Class windowClass = [UIWindow class];
    SEL selector = @selector(motionEnded:withEvent:);
    Method inherited = class_getInstanceMethod(windowClass, selector);
    if (!inherited) {
        return;
    }
    IMP inheritedImplementation = method_getImplementation(inherited);
    if (class_addMethod(windowClass, selector, (IMP)spmod_motionEnded, method_getTypeEncoding(inherited))) {
        spmodOriginalMotionEnded = inheritedImplementation;
    } else {
        Method own = class_getInstanceMethod(windowClass, selector);
        spmodOriginalMotionEnded = method_setImplementation(own, (IMP)spmod_motionEnded);
    }
}

static void spmod_installCanvasHook(void) {
    Class assetClass = [AVURLAsset class];
    SEL selector = @selector(initWithURL:options:);
    Method method = class_getInstanceMethod(assetClass, selector);
    if (!method) {
        return;
    }
    if (class_addMethod(assetClass, selector, (IMP)spmod_assetInit, method_getTypeEncoding(method))) {
        spmodOriginalAssetInit = (id (*)(id, SEL, NSURL *, NSDictionary *))method_getImplementation(method);
    } else {
        spmodOriginalAssetInit = (id (*)(id, SEL, NSURL *, NSDictionary *))method_setImplementation(method, (IMP)spmod_assetInit);
    }
}

static id (*spmodOriginalDefaultConfiguration)(id, SEL) = NULL;
static id (*spmodOriginalEphemeralConfiguration)(id, SEL) = NULL;

static NSURLSessionConfiguration *spmod_withPrivacyProtocol(NSURLSessionConfiguration *configuration) {
    Class protocolClass = NSClassFromString(@"SPModPrivacyProtocol");
    if (!protocolClass || ![configuration isKindOfClass:[NSURLSessionConfiguration class]]) {
        return configuration;
    }
    NSMutableArray *classes = [NSMutableArray arrayWithArray:configuration.protocolClasses ?: @[]];
    if (![classes containsObject:protocolClass]) {
        [classes insertObject:protocolClass atIndex:0];
        configuration.protocolClasses = classes;
    }
    return configuration;
}

static id spmod_defaultConfiguration(id self, SEL _cmd) {
    return spmod_withPrivacyProtocol(spmodOriginalDefaultConfiguration(self, _cmd));
}

static id spmod_ephemeralConfiguration(id self, SEL _cmd) {
    return spmod_withPrivacyProtocol(spmodOriginalEphemeralConfiguration(self, _cmd));
}

static void spmod_installPrivacyHook(void) {
    Class protocolClass = NSClassFromString(@"SPModPrivacyProtocol");
    if (!protocolClass) {
        return;
    }
    [NSURLProtocol registerClass:protocolClass];

    Class metaClass = object_getClass([NSURLSessionConfiguration class]);
    Method defaultMethod = class_getClassMethod([NSURLSessionConfiguration class], @selector(defaultSessionConfiguration));
    Method ephemeralMethod = class_getClassMethod([NSURLSessionConfiguration class], @selector(ephemeralSessionConfiguration));

    if (defaultMethod) {
        IMP original = method_getImplementation(defaultMethod);
        if (class_addMethod(metaClass, @selector(defaultSessionConfiguration), (IMP)spmod_defaultConfiguration, method_getTypeEncoding(defaultMethod))) {
            spmodOriginalDefaultConfiguration = (id (*)(id, SEL))original;
        } else {
            spmodOriginalDefaultConfiguration = (id (*)(id, SEL))method_setImplementation(defaultMethod, (IMP)spmod_defaultConfiguration);
        }
    }

    if (ephemeralMethod) {
        IMP original = method_getImplementation(ephemeralMethod);
        if (class_addMethod(metaClass, @selector(ephemeralSessionConfiguration), (IMP)spmod_ephemeralConfiguration, method_getTypeEncoding(ephemeralMethod))) {
            spmodOriginalEphemeralConfiguration = (id (*)(id, SEL))original;
        } else {
            spmodOriginalEphemeralConfiguration = (id (*)(id, SEL))method_setImplementation(ephemeralMethod, (IMP)spmod_ephemeralConfiguration);
        }
    }
}

__attribute__((constructor)) static void init() {
    // Initialize Orion - do not remove this line.
    orion_init();

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    id copyOnShake = [defaults objectForKey:@"copyTrackOnShake"];
    if (![copyOnShake isKindOfClass:[NSNumber class]] || [copyOnShake boolValue]) {
        spmod_installShakeHook();
    }

    if ([defaults boolForKey:@"disableCanvas"]) {
        spmod_installCanvasHook();
    }

    NSString *privacyMode = [defaults stringForKey:@"privacyMode"];
    if (![privacyMode isEqualToString:@"off"]) {
        spmod_installPrivacyHook();
    }
}
