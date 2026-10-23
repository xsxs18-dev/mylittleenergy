#import "VXShared.h"
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>

#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
#import <roothide.h>
#endif

NSString *VXJailbreakPath(NSString *path) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(path);
#else
    return [@"/var/jb" stringByAppendingString:path];
#endif
}

NSString *VXDataDirectory(void) {
#ifdef THEOS_PACKAGE_SCHEME_ROOTHIDE
    return jbroot(@"/var/mobile/Library/MyLittleEnergy");
#else
    return @"/var/mobile/Library/MyLittleEnergy";
#endif
}

#define VX_MOBILE_UID 501

static int64_t VXClamp(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

#pragma mark - Live

uint64_t VXLivePack(VXLive live) {
	if (!live.valid) return 0;
	uint64_t state = (uint64_t)VXClamp(live.level, 0, 127);
	if (live.charging) state |= 1ull << 7;
	if (live.external) state |= 1ull << 8;
	if (live.full) state |= 1ull << 9;
	if (live.held) state |= 1ull << 10;
	state |= 1ull << 11;
	int64_t power = VXClamp(llround(live.power * 10), -2048, 2047);
	state |= ((uint64_t)power & 0xFFF) << 12;
	state |= (uint64_t)VXClamp(llround((live.temperature + 50) * 10), 0, 2047) << 24;
	uint64_t minutes = live.minutes < 0 ? 0x3FFF : (uint64_t)VXClamp(live.minutes, 0, 0x3FFE);
	state |= minutes << 35;
	state |= (uint64_t)VXClamp(live.health, 0, 127) << 49;
	state |= (uint64_t)VXClamp(live.adapterWatts, 0, 255) << 56;
	return state;
}

VXLive VXLiveUnpack(uint64_t state) {
	VXLive live = {0};
	live.valid = (state >> 11) & 1;
	if (!live.valid) {
		live.minutes = -1;
		return live;
	}
	live.level = state & 0x7F;
	live.charging = (state >> 7) & 1;
	live.external = (state >> 8) & 1;
	live.full = (state >> 9) & 1;
	live.held = (state >> 10) & 1;
	int64_t power = (state >> 12) & 0xFFF;
	if (power & 0x800) power -= 0x1000;
	live.power = power / 10.0;
	live.temperature = ((state >> 24) & 0x7FF) / 10.0 - 50;
	uint64_t minutes = (state >> 35) & 0x3FFF;
	live.minutes = minutes == 0x3FFF ? -1 : (NSInteger)minutes;
	live.health = (state >> 49) & 0x7F;
	live.adapterWatts = (state >> 56) & 0xFF;
	return live;
}

#pragma mark - Look

uint64_t VXLookPack(VXLook look) {
	uint64_t state = (uint64_t)VXClamp(look.statusBarMode, 0, 3);
	state |= ((uint64_t)look.statusBarFields & 0x3F) << 2;
	if (look.statusBarOnlyCharging) state |= 1ull << 8;
	state |= (uint64_t)VXClamp(look.iconMode, 0, 3) << 9;
	if (look.iconChargingCustom) state |= 1ull << 11;
	state |= (uint64_t)VXClamp(look.iconLowThreshold, 0, 100) << 12;
	if (look.fahrenheit) state |= 1ull << 19;
	if (look.enabled) state |= 1ull << 20;
	return state;
}

VXLook VXLookUnpack(uint64_t state) {
	VXLook look;
	look.statusBarMode = state & 0x3;
	look.statusBarFields = (state >> 2) & 0x3F;
	look.statusBarOnlyCharging = (state >> 8) & 1;
	look.iconMode = (state >> 9) & 0x3;
	look.iconChargingCustom = (state >> 11) & 1;
	look.iconLowThreshold = (state >> 12) & 0x7F;
	look.fahrenheit = (state >> 19) & 1;
	look.enabled = (state >> 20) & 1;
	return look;
}

static NSString *VXPowerText(double watts) {
	double magnitude = fabs(watts);
	NSString *number = magnitude >= 10 ? [NSString stringWithFormat:@"%.0f", magnitude] : [NSString stringWithFormat:@"%.1f", magnitude];
	return [NSString stringWithFormat:@"%@%@W", watts < -0.05 ? @"−" : @"", number];
}

NSString *VXStatusBarText(VXLook look, VXLive live, NSString *separator) {
	if (!look.enabled || look.statusBarMode == VXStatusBarOff || !live.valid) return nil;
	if (look.statusBarOnlyCharging && !live.external) return nil;
	NSMutableArray *parts = [NSMutableArray array];
	NSInteger fields = look.statusBarFields;
	if (fields & VXFieldPercent) [parts addObject:[NSString stringWithFormat:@"%ld%%", (long)live.level]];
	if (fields & VXFieldPower) [parts addObject:VXPowerText(live.power)];
	if (fields & VXFieldTemperature) {
		[parts addObject:look.fahrenheit ? [NSString stringWithFormat:@"%.0f°F", live.temperature * 9 / 5 + 32] : [NSString stringWithFormat:@"%.0f°C", live.temperature]];
	}
	if ((fields & VXFieldTime) && live.minutes >= 0) [parts addObject:[NSString stringWithFormat:@"%ld:%02ld", (long)(live.minutes / 60), (long)(live.minutes % 60)]];
	if ((fields & VXFieldAdapter) && live.external && live.adapterWatts > 0) [parts addObject:[NSString stringWithFormat:@"⚡︎%ldW", (long)live.adapterWatts]];
	if ((fields & VXFieldHealth) && live.health > 0) [parts addObject:[NSString stringWithFormat:@"♥︎%ld%%", (long)live.health]];
	return parts.count ? [parts componentsJoinedByString:separator] : nil;
}

#pragma mark - Messages

uint64_t VXMessagePack(NSInteger type, NSInteger value, NSInteger sequence) {
	return ((uint64_t)VXClamp(type, 0, 255)) | ((uint64_t)VXClamp(value, 0, 0xFFFFFF) << 8) | ((uint64_t)(sequence & 0xFFFF) << 32);
}

void VXMessageUnpack(uint64_t state, NSInteger *type, NSInteger *value) {
	if (type) *type = state & 0xFF;
	if (value) *value = (state >> 8) & 0xFFFFFF;
}

#pragma mark - Notify

static int VXToken(const char *name) {
	static NSMutableDictionary<NSString *, NSNumber *> *tokens;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tokens = [NSMutableDictionary new]; });
	NSString *key = @(name);
	@synchronized (tokens) {
		NSNumber *token = tokens[key];
		if (token) return token.intValue;
		int value = 0;
		if (notify_register_check(name, &value) != NOTIFY_STATUS_OK) return -1;
		tokens[key] = @(value);
		return value;
	}
}

void VXPost(const char *name) {
	notify_post(name);
}

void VXPostState(const char *name, uint64_t state) {
	int token = VXToken(name);
	if (token >= 0) notify_set_state(token, state);
	notify_post(name);
}

uint64_t VXGetState(const char *name) {
	int token = VXToken(name);
	uint64_t state = 0;
	if (token >= 0) notify_get_state(token, &state);
	return state;
}

int VXObserve(const char *name, void (^handler)(uint64_t state)) {
	int token = 0;
	notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
		uint64_t state = 0;
		notify_get_state(t, &state);
		handler(state);
	});
	return token;
}

#pragma mark - Settings

NSDictionary *VXSettingsDefaults(void) {
	static NSDictionary *defaults;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		defaults = @{
			@"enabled": @YES,
			@"tempUnit": @0,
			@"sampleInterval": @60,
			@"retentionDays": @90,
			@"accentColor": @"#32D74B",

			@"limitEnabled": @NO,
			@"limitMax": @80,
			@"limitResume": @75,
			@"limitMode": @0,
			@"heatEnabled": @NO,
			@"heatMax": @40,
			@"scheduleEnabled": @NO,
			@"scheduleHour": @6,
			@"scheduleMinute": @0,
			@"scheduleWindow": @240,

			@"sbMode": @0,
			@"sbFields": @(VXFieldPower | VXFieldTemperature),
			@"sbOnlyCharging": @NO,

			@"iconMode": @0,
			@"iconColor": @"#32D74B",
			@"iconChargingCustom": @NO,
			@"iconChargingColor": @"#0A84FF",
			@"iconLowThreshold": @20,

			@"hudEnabled": @NO,
			@"hudWhen": @1,
			@"hudFields": @(VXFieldPower | VXFieldTemperature | VXFieldPercent),
			@"hudSize": @0,
			@"hudOpacity": @0.92,
			@"hudHideLock": @YES,

			@"animEnabled": @NO,
			@"animStyle": @0,
			@"animDuration": @4,
			@"animHideNative": @YES,
			@"animDetails": @YES,

			@"alertsEnabled": @YES,
			@"alertLevels": @[
				@{@"level": @20, @"up": @NO, @"enabled": @YES},
				@{@"level": @80, @"up": @YES, @"enabled": @NO},
			],
			@"alertFull": @NO,
			@"alertHot": @NO,
			@"alertHotTemp": @40,
			@"alertLimit": @YES,
			@"alertBanner": @YES,
			@"alertSpeech": @NO,
			@"alertSound": @"low_power.caf",
			@"plugSoundEnabled": @NO,
			@"plugSound": @"connect_power.caf",
			@"unplugSoundEnabled": @NO,
			@"unplugSound": @"Tock.caf",

			@"rules": @[],
			@"keepLowPower": @NO,
		};
	});
	return defaults;
}

NSDictionary *VXReadSettings(void) {
	NSMutableDictionary *settings = [VXSettingsDefaults() mutableCopy];
	NSDictionary *stored = VXReadPlist(VX_SETTINGS_PATH);
	if (stored) [settings addEntriesFromDictionary:stored];
	return settings;
}

BOOL VXWriteSettings(NSDictionary *settings) {
	NSDictionary *defaults = VXSettingsDefaults();
	NSMutableDictionary *changed = [NSMutableDictionary dictionary];
	[settings enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
		if (![defaults[key] isEqual:value]) changed[key] = value;
	}];
	BOOL ok = VXWritePlist(VX_SETTINGS_PATH, changed);
	VXPost(VX_NOTIFY_SETTINGS);
	return ok;
}

BOOL VXSettingBool(NSDictionary *settings, NSString *key) {
	id value = settings[key] ?: VXSettingsDefaults()[key];
	return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
}

NSInteger VXSettingInt(NSDictionary *settings, NSString *key) {
	id value = settings[key] ?: VXSettingsDefaults()[key];
	return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

double VXSettingDouble(NSDictionary *settings, NSString *key) {
	id value = settings[key] ?: VXSettingsDefaults()[key];
	return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
}

VXLook VXLookFromSettings(NSDictionary *settings) {
	VXLook look;
	look.enabled = VXSettingBool(settings, @"enabled");
	look.statusBarMode = VXSettingInt(settings, @"sbMode");
	look.statusBarFields = VXSettingInt(settings, @"sbFields");
	look.statusBarOnlyCharging = VXSettingBool(settings, @"sbOnlyCharging");
	look.iconMode = VXSettingInt(settings, @"iconMode");
	look.iconChargingCustom = VXSettingBool(settings, @"iconChargingCustom");
	look.iconLowThreshold = VXSettingInt(settings, @"iconLowThreshold");
	look.fahrenheit = VXSettingInt(settings, @"tempUnit") == 1;
	return look;
}

int32_t VXParseHexColor(NSString *hex) {
	if (![hex isKindOfClass:[NSString class]]) return -1;
	NSString *clean = [hex stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"# "]];
	if (clean.length != 6) return -1;
	unsigned int value = 0;
	if (![[NSScanner scannerWithString:clean] scanHexInt:&value]) return -1;
	return (int32_t)(value & 0xFFFFFF);
}

#pragma mark - Files

static void VXHandToMobile(NSString *path, mode_t mode) {
	if (getuid() != 0) return;
	chown(path.fileSystemRepresentation, VX_MOBILE_UID, VX_MOBILE_UID);
	chmod(path.fileSystemRepresentation, mode);
}

void VXEnsureDirectory(void) {
	BOOL isDirectory = NO;
	if ([NSFileManager.defaultManager fileExistsAtPath:VX_DIR isDirectory:&isDirectory] && isDirectory) return;
	[NSFileManager.defaultManager createDirectoryAtPath:VX_DIR withIntermediateDirectories:YES attributes:nil error:nil];
	VXHandToMobile(VX_DIR, 0755);
}

BOOL VXWriteFile(NSString *path, NSData *data) {
	if (!data) return NO;
	VXEnsureDirectory();
	BOOL ok = [data writeToFile:path options:NSDataWritingAtomic error:nil];
	if (ok) VXHandToMobile(path, 0644);
	return ok;
}

id VXReadJSON(NSString *path) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

BOOL VXWriteJSON(NSString *path, id object) {
	if (!object || ![NSJSONSerialization isValidJSONObject:object]) return NO;
	return VXWriteFile(path, [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]);
}

NSDictionary *VXReadPlist(NSString *path) {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) return nil;
	id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil];
	return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

BOOL VXWritePlist(NSString *path, NSDictionary *plist) {
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist ?: @{} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
	return VXWriteFile(path, data);
}

#pragma mark - Strings

NSString *VXL(NSString *key) {
	static NSBundle *bundle;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		bundle = [NSBundle bundleWithPath:VX_APP_PATH] ?: NSBundle.mainBundle;
	});
	return [bundle localizedStringForKey:key value:key table:nil];
}
