#import "VXSBController.h"
#import "VXShared.h"
#import "VXBattery.h"
#import "VXBanner.h"
#import "VXHUD.h"
#import "VXActions.h"
#import "VXChargeAnimation.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

#ifndef VX_VERSION
#define VX_VERSION "0"
#endif

typedef UInt32 VXSoundID;
static OSStatus (*pAudioServicesCreateSystemSoundID)(CFURLRef, VXSoundID *);
static void (*pAudioServicesPlaySystemSound)(VXSoundID);

static UIColor *VXColor(NSString *hex, UIColor *fallback) {
	int32_t rgb = VXParseHexColor(hex);
	if (rgb < 0) return fallback;
	return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

@implementation VXSBController {
	NSDictionary *_settings;
	NSMutableDictionary<NSString *, NSNumber *> *_sounds;
	id _synthesizer;
	UIDeviceBatteryState _batteryState;
	BOOL _lowPower;
	BOOL _locked;
	NSDate *_lastAnimation;
	BOOL _launched;
}

+ (instancetype)shared {
	static VXSBController *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [VXSBController new]; });
	return shared;
}

- (void)start {
	_settings = VXReadSettings();
	_sounds = [NSMutableDictionary dictionary];
	dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox", RTLD_LAZY);
	pAudioServicesCreateSystemSoundID = dlsym(RTLD_DEFAULT, "AudioServicesCreateSystemSoundID");
	pAudioServicesPlaySystemSound = dlsym(RTLD_DEFAULT, "AudioServicesPlaySystemSound");

	__weak VXSBController *weakSelf = self;
	VXObserve(VX_NOTIFY_SETTINGS, ^(uint64_t state) {
		VXSBController *controller = weakSelf;
		if (!controller) return;
		controller->_settings = VXReadSettings();
		[controller updateHUD];
		[controller writeStatus];
	});
	VXObserve(VX_NOTIFY_EVENT, ^(uint64_t state) {
		NSInteger type = 0, value = 0;
		VXMessageUnpack(state, &type, &value);
		[weakSelf handleEvent:type value:value];
	});
	VXObserve(VX_NOTIFY_ACTION, ^(uint64_t state) {
		NSInteger type = 0, value = 0;
		VXMessageUnpack(state, &type, &value);
		VXSBController *controller = weakSelf;
		if (controller && controller->_launched && [controller enabled]) [VXActions.shared perform:type value:value];
	});
	VXObserve(VX_NOTIFY_SB_TEST, ^(uint64_t state) {
		[weakSelf handleTest:state];
	});
	VXObserve("com.apple.springboard.lockstate", ^(uint64_t state) {
		VXSBController *controller = weakSelf;
		if (!controller) return;
		controller->_locked = state != 0;
		[controller updateHUD];
	});

	// start is called only after SpringBoard's launch notification.
	dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf didFinishLaunching]; });
}

- (NSDictionary *)settings {
	return _settings;
}

// Runs a few seconds after SpringBoard finished launching, so nothing here can hold up its start.
- (void)didFinishLaunching {
	_launched = YES;
	UIDevice *device = UIDevice.currentDevice;
	device.batteryMonitoringEnabled = YES;
	_batteryState = device.batteryState;
	_lowPower = NSProcessInfo.processInfo.lowPowerModeEnabled;
	_locked = [self lockScreenShowing];
	__weak VXSBController *weakSelf = self;
	[NSNotificationCenter.defaultCenter addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[weakSelf batteryStateChanged];
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
		[weakSelf lowPowerChanged];
	}];
	[self updateHUD];
	[self writeStatus];
}

#pragma mark - State

- (BOOL)enabled {
	return VXSettingBool(_settings, @"enabled");
}

// Only asks an existing manager; creating it ourselves during launch would change SpringBoard's start order.
- (BOOL)lockScreenShowing {
	Class managerClass = NSClassFromString(@"SBLockScreenManager");
	SEL shared = NSSelectorFromString(@"sharedInstanceIfExists");
	if (![managerClass respondsToSelector:shared]) return _locked;
	id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, shared);
	if (!manager) return _locked;
	SEL locked = NSSelectorFromString(@"isUILocked");
	return [manager respondsToSelector:locked] && ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
}

- (BOOL)plugged {
	UIDeviceBatteryState state = UIDevice.currentDevice.batteryState;
	return state == UIDeviceBatteryStateCharging || state == UIDeviceBatteryStateFull;
}

- (BOOL)hidesNativeChargingView {
	return [self enabled] && VXSettingBool(_settings, @"animEnabled") && VXSettingBool(_settings, @"animHideNative");
}

- (void)updateHUD {
	if (!_launched) return;
	NSMutableDictionary *effective = [_settings mutableCopy];
	effective[@"enabled"] = @([self enabled]);
	[VXHUD.shared updateWithSettings:effective locked:_locked plugged:[self plugged]];
}

#pragma mark - Charger

- (void)batteryStateChanged {
	UIDeviceBatteryState previous = _batteryState;
	_batteryState = UIDevice.currentDevice.batteryState;
	BOOL wasPlugged = previous == UIDeviceBatteryStateCharging || previous == UIDeviceBatteryStateFull;
	BOOL plugged = [self plugged];
	[self updateHUD];
	if (!wasPlugged && plugged) [self chargerConnected];
}

- (void)chargerConnected {
	if (![self enabled] || !VXSettingBool(_settings, @"animEnabled")) return;
	if (_lastAnimation && -_lastAnimation.timeIntervalSinceNow < 5) return;
	if (![self lockScreenShowing]) return;
	[self showAnimation];
}

- (void)showAnimation {
	_lastAnimation = [NSDate date];
	[VXChargeAnimation showWithStyle:VXSettingInt(_settings, @"animStyle")
		duration:VXSettingDouble(_settings, @"animDuration")
		details:VXSettingBool(_settings, @"animDetails")
		accent:VXColor(_settings[@"accentColor"], UIColor.systemGreenColor)
		fahrenheit:VXSettingInt(_settings, @"tempUnit") == 1];
}

// iOS turns Low Power Mode off once the battery charges past 80%.
- (void)lowPowerChanged {
	BOOL on = NSProcessInfo.processInfo.lowPowerModeEnabled;
	BOOL turnedOff = _lowPower && !on;
	_lowPower = on;
	if (!turnedOff || ![self enabled] || !VXSettingBool(_settings, @"keepLowPower") || ![self plugged]) return;
	float level = UIDevice.currentDevice.batteryLevel * 100;
	if (level < 79 || level > 83) return;
	[VXActions.shared turnOnLowPowerSoon];
}

#pragma mark - Events

- (NSString *)temperatureText:(double)celsius {
	if (VXSettingInt(_settings, @"tempUnit") == 1) return [NSString stringWithFormat:@"%.0f °F", celsius * 9 / 5 + 32];
	return [NSString stringWithFormat:@"%.0f °C", celsius];
}

- (void)handleEvent:(NSInteger)type value:(NSInteger)value {
	if (!_launched || ![self enabled]) return;
	NSString *title = nil, *text = nil, *symbol = @"bolt.fill";
	UIColor *color = UIColor.systemGreenColor;
	NSString *sound = _settings[@"alertSound"];
	switch (type) {
		case VXEventLevelDown:
			title = VXL(@"Battery Low");
			text = [NSString stringWithFormat:VXL(@"Battery is at %ld%%."), (long)value];
			symbol = @"battery.25";
			color = value <= 20 ? UIColor.systemRedColor : UIColor.systemOrangeColor;
			break;
		case VXEventLevelUp:
			title = VXL(@"Battery Level Reached");
			text = [NSString stringWithFormat:VXL(@"Battery is at %ld%%."), (long)value];
			symbol = @"battery.75";
			break;
		case VXEventFull:
			title = VXL(@"Fully Charged");
			text = VXL(@"Your battery is full.");
			symbol = @"battery.100";
			break;
		case VXEventHot:
			title = VXL(@"Battery Is Hot");
			text = [NSString stringWithFormat:VXL(@"Battery temperature is %@."), [self temperatureText:value / 10.0]];
			symbol = @"thermometer";
			color = UIColor.systemOrangeColor;
			break;
		case VXEventLimitReached:
			title = VXL(@"Charge Limit Reached");
			text = [NSString stringWithFormat:VXL(@"Charging paused at %ld%%."), (long)value];
			symbol = @"bolt.slash.fill";
			color = UIColor.systemTealColor;
			break;
		case VXEventHeatPause:
			title = VXL(@"Charging Paused");
			text = [NSString stringWithFormat:VXL(@"The battery is %@. Charging continues when it cools down."), [self temperatureText:value / 10.0]];
			symbol = @"thermometer";
			color = UIColor.systemOrangeColor;
			break;
		case VXEventRuleFired: {
			NSArray *rules = _settings[@"rules"];
			NSDictionary *rule = [rules isKindOfClass:[NSArray class]] && value >= 0 && value < (NSInteger)rules.count ? rules[value] : nil;
			title = VXL(@"Automation");
			text = [rule isKindOfClass:[NSDictionary class]] ? (rule[@"title"] ?: rule[@"name"]) : nil;
			symbol = @"wand.and.stars";
			color = UIColor.systemPurpleColor;
			sound = nil;
			break;
		}
		case VXEventPlugged:
			if (VXSettingBool(_settings, @"plugSoundEnabled")) [self playSound:_settings[@"plugSound"]];
			// The daemon also notices chargers that UIKit reported late.
			[self chargerConnected];
			return;
		case VXEventUnplugged:
			if (VXSettingBool(_settings, @"unplugSoundEnabled")) [self playSound:_settings[@"unplugSound"]];
			return;
		case VXEventTest:
			title = @"MyLittleEnergy";
			text = VXL(@"Alerts are working.");
			symbol = @"checkmark.circle.fill";
			break;
		default:
			return;
	}
	[self alertTitle:title text:text symbol:symbol color:color sound:sound];
}

- (void)alertTitle:(NSString *)title text:(NSString *)text symbol:(NSString *)symbol color:(UIColor *)color sound:(NSString *)sound {
	if (VXSettingBool(_settings, @"alertBanner")) [VXBanner showTitle:title text:text symbol:symbol color:color];
	if (sound.length) [self playSound:sound];
	if (VXSettingBool(_settings, @"alertSpeech")) [self speak:text.length ? text : title];
}

- (void)handleTest:(uint64_t)state {
	if (!_launched || ![self enabled]) return;
	switch ((NSInteger)state) {
		case VXSBTestStatus: [self writeStatus]; break;
		case VXSBTestAnimation: [self showAnimation]; break;
		case VXSBTestBanner: [self alertTitle:@"MyLittleEnergy" text:VXL(@"Alerts are working.") symbol:@"checkmark.circle.fill" color:UIColor.systemGreenColor sound:_settings[@"alertSound"]]; break;
		case VXSBTestSound: [self playSound:_settings[@"alertSound"]]; break;
	}
}

#pragma mark - Sound and speech

- (void)playSound:(NSString *)name {
	if (![name isKindOfClass:[NSString class]] || !name.length || !pAudioServicesCreateSystemSoundID || !pAudioServicesPlaySystemSound) return;
	NSString *path = name.isAbsolutePath ? name : [@"/System/Library/Audio/UISounds" stringByAppendingPathComponent:name];
	NSNumber *cached = _sounds[path];
	if (!cached) {
		if (![NSFileManager.defaultManager fileExistsAtPath:path]) return;
		VXSoundID sound = 0;
		if (pAudioServicesCreateSystemSoundID((__bridge CFURLRef)[NSURL fileURLWithPath:path], &sound) != 0) return;
		cached = _sounds[path] = @(sound);
	}
	pAudioServicesPlaySystemSound(cached.unsignedIntValue);
}

- (void)speak:(NSString *)text {
	if (!text.length) return;
	if (!_synthesizer) {
		dlopen("/System/Library/Frameworks/AVFAudio.framework/AVFAudio", RTLD_LAZY);
		dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_LAZY);
		_synthesizer = [NSClassFromString(@"AVSpeechSynthesizer") new];
	}
	Class utteranceClass = NSClassFromString(@"AVSpeechUtterance");
	Class voiceClass = NSClassFromString(@"AVSpeechSynthesisVoice");
	SEL make = NSSelectorFromString(@"speechUtteranceWithString:");
	SEL speak = NSSelectorFromString(@"speakUtterance:");
	if (!_synthesizer || ![utteranceClass respondsToSelector:make] || ![_synthesizer respondsToSelector:speak]) return;
	id utterance = ((id (*)(id, SEL, NSString *))objc_msgSend)(utteranceClass, make, text);
	SEL voiceWithLanguage = NSSelectorFromString(@"voiceWithLanguage:");
	NSString *language = NSLocale.preferredLanguages.firstObject;
	if (language && [voiceClass respondsToSelector:voiceWithLanguage] && [utterance respondsToSelector:NSSelectorFromString(@"setVoice:")]) {
		id voice = ((id (*)(id, SEL, NSString *))objc_msgSend)(voiceClass, voiceWithLanguage, language);
		if (voice) [utterance setValue:voice forKey:@"voice"];
	}
	((void (*)(id, SEL, id))objc_msgSend)(_synthesizer, speak, utterance);
}

#pragma mark - Status for the app's diagnostics page

- (void)writeStatus {
	Class coverSheet = NSClassFromString(@"CSCoverSheetViewController");
	BOOL chargingHook = [coverSheet instancesRespondToSelector:NSSelectorFromString(@"_transitionChargingViewToVisible:showBattery:animated:")]
		|| [coverSheet instancesRespondToSelector:NSSelectorFromString(@"_transitionChargingViewToVisible:suppressedByPack:showBattery:animated:")];
	VXActions *actions = VXActions.shared;
	NSDictionary *status = @{
		@"safeMode": @NO,
		@"version": @VX_VERSION,
		@"pid": @(getpid()),
		@"time": @(NSDate.date.timeIntervalSince1970),
		@"launched": @(_launched),
		@"lockScreenManager": @(NSClassFromString(@"SBLockScreenManager") != nil),
		@"chargingViewHook": @(chargingHook),
		@"batteryView": @(NSClassFromString(@"_UIBatteryView") != nil),
		@"statusBarTime": @(NSClassFromString(@"_UIStatusBarTimeItem") != nil),
		@"sounds": @(pAudioServicesPlaySystemSound != NULL),
		@"speech": @(NSClassFromString(@"AVSpeechSynthesizer") != nil || dlopen("/System/Library/Frameworks/AVFAudio.framework/AVFAudio", RTLD_NOLOAD) != NULL),
		@"actions": @{
			@"lowPower": @([actions canPerform:VXActionLowPower]),
			@"wifi": @([actions canPerform:VXActionWiFi]),
			@"bluetooth": @([actions canPerform:VXActionBluetooth]),
			@"brightness": @([actions canPerform:VXActionBrightness]),
			@"darkMode": @([actions canPerform:VXActionDarkMode]),
			@"airplane": @([actions canPerform:VXActionAirplane]),
			@"location": @([actions canPerform:VXActionLocation]),
		},
	};
	VXWritePlist(VX_SB_STATUS_PATH, status);
	VXPost(VX_NOTIFY_SB_STATUS);
}

@end
