#import "VXActions.h"
#import "VXShared.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

// Nothing here may run while SpringBoard is launching: several of these clients talk to
// services that SpringBoard itself provides (the interface style for example), and a
// synchronous call from SpringBoard's main thread to itself never returns. So availability
// checks only look at classes, and anything that talks to another process runs on a
// background queue.

static BOOL VXResponds(id target, NSString *selector) {
	return target && [target respondsToSelector:NSSelectorFromString(selector)];
}

static BOOL VXInstancesRespond(NSString *className, NSString *selector) {
	return [NSClassFromString(className) instancesRespondToSelector:NSSelectorFromString(selector)];
}

static id VXSend(id target, NSString *selector) {
	return VXResponds(target, selector) ? ((id (*)(id, SEL))objc_msgSend)(target, NSSelectorFromString(selector)) : nil;
}

static void VXSendSetBool(id target, NSString *selector, BOOL value) {
	if (VXResponds(target, selector)) ((void (*)(id, SEL, BOOL))objc_msgSend)(target, NSSelectorFromString(selector), value);
}

static id VXSingleton(NSString *className, NSString *selector) {
	return VXSend(NSClassFromString(className), selector);
}

typedef const void *VXWiFiClientRef;
static VXWiFiClientRef (*pWiFiManagerClientCreate)(CFAllocatorRef, int);
static Boolean (*pWiFiManagerClientSetProperty)(VXWiFiClientRef, CFStringRef, CFPropertyListRef);
static void (*pBKSDisplayBrightnessSet)(float, int);

@implementation VXActions {
	dispatch_queue_t _queue;
	VXWiFiClientRef _wifiClient;
	id _styleMode;
	id _radios;
	BOOL _loaded;
}

+ (instancetype)shared {
	static VXActions *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [VXActions new]; });
	return shared;
}

- (instancetype)init {
	if ((self = [super init])) {
		_queue = dispatch_queue_create("com.xsxs18.mylittleenergy.actions", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (void)load {
	if (_loaded) return;
	_loaded = YES;
	for (NSString *path in @[
		@"/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi",
		@"/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager",
		@"/System/Library/Frameworks/CoreLocation.framework/CoreLocation",
		@"/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport",
		@"/System/Library/PrivateFrameworks/LowPowerMode.framework/LowPowerMode",
		@"/System/Library/PrivateFrameworks/CoreDuet.framework/CoreDuet",
		@"/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
		@"/System/Library/PrivateFrameworks/UIKitServices.framework/UIKitServices",
	]) dlopen(path.fileSystemRepresentation, RTLD_LAZY);
	pWiFiManagerClientCreate = dlsym(RTLD_DEFAULT, "WiFiManagerClientCreate");
	pWiFiManagerClientSetProperty = dlsym(RTLD_DEFAULT, "WiFiManagerClientSetProperty");
	pBKSDisplayBrightnessSet = dlsym(RTLD_DEFAULT, "BKSDisplayBrightnessSet");
}

- (BOOL)canPerform:(NSInteger)action {
	[self load];
	switch (action) {
		case VXActionLowPower:
			return VXInstancesRespond(@"_PMLowPowerMode", @"setPowerMode:fromSource:withCompletion:")
				|| VXInstancesRespond(@"_PMLowPowerMode", @"setPowerMode:fromSource:")
				|| VXInstancesRespond(@"_CDBatterySaver", @"setMode:");
		case VXActionWiFi:
			return VXInstancesRespond(@"SBWiFiManager", @"setWiFiEnabled:") || (pWiFiManagerClientCreate && pWiFiManagerClientSetProperty);
		case VXActionBluetooth:
			return VXInstancesRespond(@"BluetoothManager", @"setEnabled:");
		case VXActionBrightness:
			return VXInstancesRespond(@"SBBrightnessController", @"setBrightnessLevel:animated:") || pBKSDisplayBrightnessSet;
		case VXActionDarkMode:
			return VXInstancesRespond(@"UISUserInterfaceStyleMode", @"setModeValue:");
		case VXActionAirplane:
			return VXInstancesRespond(@"SBAirplaneModeController", @"setInAirplaneMode:") || VXInstancesRespond(@"RadiosPreferences", @"setAirplaneMode:");
		case VXActionLocation:
			return [NSClassFromString(@"CLLocationManager") respondsToSelector:NSSelectorFromString(@"setLocationServicesEnabled:")];
	}
	return NO;
}

- (void)perform:(NSInteger)action value:(NSInteger)value {
	[self load];
	BOOL on = value != 0;
	// SpringBoard's own controllers live on the main thread; clients of other daemons, or of
	// services SpringBoard hosts itself, run on the actions queue.
	BOOL mainThread = action == VXActionWiFi || action == VXActionBluetooth || action == VXActionBrightness || action == VXActionAirplane;
	dispatch_async(mainThread ? dispatch_get_main_queue() : _queue, ^{
		if (action == VXActionWiFi) [self setWiFi:on];
		else if (action == VXActionBluetooth) [self setBluetooth:on];
		else if (action == VXActionBrightness) [self setBrightness:MIN(MAX(value, 0), 100) / 100.0f];
		else if (action == VXActionAirplane) [self setAirplane:on];
		else if (action == VXActionLowPower) [self setLowPower:on];
		else if (action == VXActionDarkMode) [self setDarkMode:on];
		else if (action == VXActionLocation) VXSendSetBool(NSClassFromString(@"CLLocationManager"), @"setLocationServicesEnabled:", on);
	});
}

#pragma mark - Low Power Mode

- (id)lowPowerTarget {
	id lowPowerMode = VXSingleton(@"_PMLowPowerMode", @"sharedInstance");
	if (VXResponds(lowPowerMode, @"setPowerMode:fromSource:withCompletion:") || VXResponds(lowPowerMode, @"setPowerMode:fromSource:")) return lowPowerMode;
	id saver = VXSingleton(@"_CDBatterySaver", @"batterySaver");
	return VXResponds(saver, @"setMode:") ? saver : nil;
}

- (void)setLowPower:(BOOL)on {
	[self load];
	if (NSProcessInfo.processInfo.lowPowerModeEnabled == on) return;
	id target = [self lowPowerTarget];
	SEL withCompletion = NSSelectorFromString(@"setPowerMode:fromSource:withCompletion:");
	SEL plain = NSSelectorFromString(@"setPowerMode:fromSource:");
	if ([target respondsToSelector:withCompletion]) {
		((void (*)(id, SEL, long long, NSString *, id))objc_msgSend)(target, withCompletion, on ? 1 : 0, @"SpringBoard", ^(BOOL success, NSError *error) {});
	} else if ([target respondsToSelector:plain]) {
		((BOOL (*)(id, SEL, long long, NSString *))objc_msgSend)(target, plain, on ? 1 : 0, @"SpringBoard");
	} else if ([target respondsToSelector:NSSelectorFromString(@"setMode:")]) {
		((BOOL (*)(id, SEL, long long))objc_msgSend)(target, NSSelectorFromString(@"setMode:"), on ? 1 : 0);
	}
}

- (void)turnOnLowPowerSoon {
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), _queue, ^{ [self setLowPower:YES]; });
}

#pragma mark - Radios

- (void)setWiFi:(BOOL)on {
	id manager = VXSingleton(@"SBWiFiManager", @"sharedInstance");
	if (VXResponds(manager, @"setWiFiEnabled:")) {
		VXSendSetBool(manager, @"setWiFiEnabled:", on);
		return;
	}
	if (!_wifiClient && pWiFiManagerClientCreate) _wifiClient = pWiFiManagerClientCreate(kCFAllocatorDefault, 0);
	if (_wifiClient && pWiFiManagerClientSetProperty) pWiFiManagerClientSetProperty(_wifiClient, CFSTR("AllowEnable"), on ? kCFBooleanTrue : kCFBooleanFalse);
}

- (void)setBluetooth:(BOOL)on {
	id manager = VXSingleton(@"BluetoothManager", @"sharedInstance");
	if (on) VXSendSetBool(manager, @"setPowered:", YES);
	VXSendSetBool(manager, @"setEnabled:", on);
	if (!on) VXSendSetBool(manager, @"setPowered:", NO);
}

- (void)setAirplane:(BOOL)on {
	id controller = VXSingleton(@"SBAirplaneModeController", @"sharedInstance");
	if (VXResponds(controller, @"setInAirplaneMode:")) {
		VXSendSetBool(controller, @"setInAirplaneMode:", on);
		return;
	}
	if (!_radios) {
		Class radios = NSClassFromString(@"RadiosPreferences");
		if (radios) _radios = [radios new];
	}
	VXSendSetBool(_radios, @"setAirplaneMode:", on);
}

#pragma mark - Display

- (void)setBrightness:(float)level {
	id controller = nil;
	for (NSString *selector in @[@"sharedBrightnessController", @"sharedInstance"]) {
		controller = VXSingleton(@"SBBrightnessController", selector);
		if (VXResponds(controller, @"setBrightnessLevel:animated:")) break;
		controller = nil;
	}
	if (controller) {
		((BOOL (*)(id, SEL, float, BOOL))objc_msgSend)(controller, NSSelectorFromString(@"setBrightnessLevel:animated:"), level, YES);
	} else if (pBKSDisplayBrightnessSet) {
		pBKSDisplayBrightnessSet(level, 1);
	}
}

// UIUserInterfaceStyle raw values: 1 light, 2 dark. Runs on the actions queue, see the top of the file.
- (void)setDarkMode:(BOOL)on {
	if (!_styleMode) {
		Class mode = NSClassFromString(@"UISUserInterfaceStyleMode");
		SEL initWithDelegate = NSSelectorFromString(@"initWithDelegate:");
		if ([mode instancesRespondToSelector:initWithDelegate]) _styleMode = ((id (*)(id, SEL, id))objc_msgSend)([mode alloc], initWithDelegate, nil);
		else if (mode) _styleMode = [mode new];
	}
	if (VXResponds(_styleMode, @"setModeValue:")) ((void (*)(id, SEL, long long))objc_msgSend)(_styleMode, NSSelectorFromString(@"setModeValue:"), on ? 2 : 1);
}

@end
