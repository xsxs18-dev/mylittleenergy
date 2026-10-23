#import "VXBattery.h"
#import <dlfcn.h>
#import <mach/mach.h>

#pragma mark - IOKit (looked up at runtime, the SDK has no IOKit headers for iOS)

typedef mach_port_t vx_io_object_t;
typedef struct IONotificationPort *VXNotificationPortRef;
typedef void (*VXInterestCallback)(void *refcon, vx_io_object_t service, uint32_t type, void *argument);

static CFMutableDictionaryRef (*pIOServiceMatching)(const char *);
static vx_io_object_t (*pIOServiceGetMatchingService)(mach_port_t, CFDictionaryRef);
static kern_return_t (*pIORegistryEntryCreateCFProperties)(vx_io_object_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
static kern_return_t (*pIORegistryEntrySetCFProperties)(vx_io_object_t, CFTypeRef);
static VXNotificationPortRef (*pIONotificationPortCreate)(mach_port_t);
static void (*pIONotificationPortSetDispatchQueue)(VXNotificationPortRef, dispatch_queue_t);
static kern_return_t (*pIOServiceAddInterestNotification)(VXNotificationPortRef, vx_io_object_t, const char *, VXInterestCallback, void *, vx_io_object_t *);

static BOOL VXLoadIOKit(void) {
	static BOOL loaded;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
		pIOServiceMatching = dlsym(RTLD_DEFAULT, "IOServiceMatching");
		pIOServiceGetMatchingService = dlsym(RTLD_DEFAULT, "IOServiceGetMatchingService");
		pIORegistryEntryCreateCFProperties = dlsym(RTLD_DEFAULT, "IORegistryEntryCreateCFProperties");
		pIORegistryEntrySetCFProperties = dlsym(RTLD_DEFAULT, "IORegistryEntrySetCFProperties");
		pIONotificationPortCreate = dlsym(RTLD_DEFAULT, "IONotificationPortCreate");
		pIONotificationPortSetDispatchQueue = dlsym(RTLD_DEFAULT, "IONotificationPortSetDispatchQueue");
		pIOServiceAddInterestNotification = dlsym(RTLD_DEFAULT, "IOServiceAddInterestNotification");
		loaded = pIOServiceMatching && pIOServiceGetMatchingService && pIORegistryEntryCreateCFProperties;
	});
	return loaded;
}

// The registry entry stays valid for the life of the process, so it is looked up once.
static vx_io_object_t VXBatteryService(void) {
	static vx_io_object_t service;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		if (!VXLoadIOKit()) return;
		service = pIOServiceGetMatchingService(MACH_PORT_NULL, pIOServiceMatching("AppleSmartBattery"));
	});
	return service;
}

#pragma mark - Value helpers

static NSNumber *VXNumber(id value) {
	return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

static NSString *VXString(id value) {
	if ([value isKindOfClass:[NSString class]]) return [value length] ? value : nil;
	if ([value isKindOfClass:[NSData class]]) {
		NSString *string = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
		string = [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0 "]];
		return string.length ? string : nil;
	}
	return nil;
}

static NSDictionary *VXDictionary(id value) {
	return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}

static NSInteger VXInt(id value, NSInteger fallback) {
	NSNumber *number = VXNumber(value);
	return number ? number.integerValue : fallback;
}

static NSArray<NSNumber *> *VXNumbers(id value) {
	if (![value isKindOfClass:[NSArray class]]) return @[];
	NSMutableArray *numbers = [NSMutableArray array];
	for (id item in value) if (VXNumber(item)) [numbers addObject:item];
	return numbers;
}

// Times the driver can't estimate are reported as 65535.
static NSInteger VXMinutes(id value) {
	NSInteger minutes = VXInt(value, -1);
	return minutes < 0 || minutes >= 65535 ? -1 : minutes;
}

static int64_t VXClampInt(int64_t value, int64_t low, int64_t high) {
	return value < low ? low : (value > high ? high : value);
}

#pragma mark - VXBatteryInfo

@implementation VXBatteryInfo

+ (instancetype)current {
	vx_io_object_t service = VXBatteryService();
	if (!service) return nil;
	CFMutableDictionaryRef properties = NULL;
	if (pIORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) != KERN_SUCCESS || !properties) return nil;
	return [[self alloc] initWithProperties:(__bridge_transfer NSDictionary *)properties];
}

- (instancetype)initWithProperties:(NSDictionary *)p {
	if (!(self = [super init])) return nil;
	_raw = p;
	_date = [NSDate date];
	NSDictionary *batteryData = VXDictionary(p[@"BatteryData"]);
	NSDictionary *chargerData = VXDictionary(p[@"ChargerData"]);

	NSInteger current = VXInt(p[@"CurrentCapacity"], 0);
	NSInteger max = VXInt(p[@"MaxCapacity"], 100);
	_level = max > 0 && max != 100 ? lround(current * 100.0 / max) : current;
	_level = VXClampInt(_level, 0, 100);
	_charging = [VXNumber(p[@"IsCharging"]) boolValue];
	_externalConnected = [VXNumber(p[@"ExternalConnected"]) boolValue];
	_externalChargeCapable = [VXNumber(p[@"ExternalChargeCapable"]) boolValue];
	_fullyCharged = [VXNumber(p[@"FullyCharged"]) boolValue];

	NSNumber *temperature = VXNumber(p[@"Temperature"]);
	_temperature = temperature ? temperature.doubleValue / 100.0 : NAN;
	NSNumber *virtualTemperature = VXNumber(p[@"VirtualTemperature"]);
	_virtualTemperature = virtualTemperature ? virtualTemperature.doubleValue / 100.0 : NAN;
	NSNumber *voltage = VXNumber(p[@"Voltage"]) ?: VXNumber(p[@"AppleRawBatteryVoltage"]);
	_voltage = voltage ? voltage.doubleValue / 1000.0 : NAN;
	_averageAmperage = VXInt(p[@"Amperage"], 0);
	_amperage = VXInt(p[@"InstantAmperage"], _averageAmperage);
	_batteryPower = isnan(_voltage) ? 0 : _voltage * _amperage / 1000.0;

	_telemetry = VXDictionary(p[@"PowerTelemetryData"]);
	NSNumber *powerIn = VXNumber(_telemetry[@"SystemPowerIn"]);
	_systemPowerIn = powerIn ? powerIn.doubleValue / 1000.0 : NAN;
	NSNumber *load = VXNumber(_telemetry[@"SystemLoad"]);
	_systemLoad = load ? load.doubleValue / 1000.0 : NAN;

	_currentCapacity = VXInt(p[@"AppleRawCurrentCapacity"], -1);
	_fullChargeCapacity = VXInt(p[@"AppleRawMaxCapacity"], -1);
	_nominalCapacity = VXInt(p[@"NominalChargeCapacity"], -1);
	_designCapacity = VXInt(p[@"DesignCapacity"], VXInt(batteryData[@"DesignCapacity"], -1));
	NSNumber *systemHealth = VXNumber(p[@"MaximumCapacityPercent"]);
	if (systemHealth.doubleValue > 0) {
		_health = systemHealth.doubleValue;
		_healthFromSystem = YES;
	} else if (_designCapacity > 0 && (_nominalCapacity > 0 || _fullChargeCapacity > 0)) {
		_health = (_nominalCapacity > 0 ? _nominalCapacity : _fullChargeCapacity) * 100.0 / _designCapacity;
	} else {
		_health = NAN;
	}
	_cycleCount = VXInt(p[@"CycleCount"], VXInt(batteryData[@"CycleCount"], -1));
	_designCycleCount = VXInt(p[@"DesignCycleCount9C"], VXInt(p[@"DesignCycleCount70"], -1));
	_timeToEmpty = VXMinutes(p[@"AvgTimeToEmpty"]);
	if (_timeToEmpty < 0) _timeToEmpty = VXMinutes(p[@"TimeRemaining"]);
	_timeToFull = VXMinutes(p[@"AvgTimeToFull"]);

	_serial = VXString(p[@"Serial"]) ?: VXString(batteryData[@"Serial"]);
	_deviceName = VXString(p[@"DeviceName"]);
	_firmware = VXString(p[@"GasGaugeFirmwareVersion"]) ?: (VXNumber(p[@"GasGaugeFirmwareVersion"]) ? [p[@"GasGaugeFirmwareVersion"] stringValue] : nil);
	NSNumber *chemistry = VXNumber(batteryData[@"ChemID"]) ?: VXNumber(p[@"ChemID"]);
	_chemistry = chemistry ? [NSString stringWithFormat:@"0x%04lX", (long)chemistry.integerValue] : nil;

	_adapter = VXDictionary(p[@"AdapterDetails"]);
	_adapterName = VXString(_adapter[@"Name"]);
	_adapterManufacturer = VXString(_adapter[@"Manufacturer"]);
	_adapterDescription = VXString(_adapter[@"Description"]);
	_adapterWatts = [VXNumber(_adapter[@"Watts"]) doubleValue];
	NSNumber *adapterVoltage = VXNumber(_adapter[@"AdapterVoltage"]) ?: VXNumber(_adapter[@"Voltage"]);
	_adapterVoltage = adapterVoltage ? adapterVoltage.doubleValue / 1000.0 : NAN;
	_adapterCurrent = VXInt(_adapter[@"Current"], -1);
	_adapterWireless = [VXNumber(_adapter[@"IsWireless"]) boolValue];
	// While the inflow is blocked ExternalConnected is false, the adapter details still describe the charger.
	_adapterPresent = _adapterWatts > 0 || (_adapterDescription && ![_adapterDescription isEqualToString:@"batt"]);
	_plugged = _externalConnected || _adapterPresent;

	_cellVoltages = VXNumbers(batteryData[@"CellVoltage"]);
	_qmax = VXNumbers(batteryData[@"Qmax"]);
	_notChargingReason = VXInt(chargerData[@"NotChargingReason"], -1);
	_chargingCurrent = VXInt(chargerData[@"ChargingCurrent"], -1);
	_chargingVoltage = VXInt(chargerData[@"ChargingVoltage"], -1);
	_lifetime = VXDictionary(batteryData[@"LifetimeData"]);
	_chargeInhibited = VXNumber(p[@"PredictiveChargingInhibit"]);
	return self;
}

- (NSInteger)minutesRemaining {
	if (_charging) return _timeToFull;
	if (!_plugged) return _timeToEmpty;
	return -1;
}

- (VXLive)liveWithHeld:(BOOL)held {
	VXLive live;
	live.valid = YES;
	live.level = _level;
	live.charging = _charging;
	live.external = _plugged;
	live.full = _fullyCharged;
	live.held = held;
	live.power = _batteryPower;
	live.temperature = isnan(_temperature) ? 0 : _temperature;
	live.minutes = self.minutesRemaining;
	live.health = isnan(_health) ? 0 : lround(_health);
	live.adapterWatts = lround(_adapterWatts);
	return live;
}

- (VXSample)sampleWithFlags:(uint8_t)extraFlags {
	VXSample sample;
	memset(&sample, 0, sizeof(sample));
	sample.time = (uint32_t)_date.timeIntervalSince1970;
	sample.level = (uint8_t)_level;
	sample.flags = extraFlags;
	if (_charging) sample.flags |= VXSampleCharging;
	if (_plugged) sample.flags |= VXSampleExternal;
	if (_fullyCharged) sample.flags |= VXSampleFull;
	sample.temperature = isnan(_temperature) ? INT16_MIN : (int16_t)VXClampInt(llround(_temperature * 100), INT16_MIN + 1, INT16_MAX);
	sample.voltage = isnan(_voltage) ? 0 : (uint16_t)VXClampInt(llround(_voltage * 1000), 0, UINT16_MAX);
	sample.amperage = (int16_t)VXClampInt(_amperage, INT16_MIN + 1, INT16_MAX);
	sample.power = (int16_t)VXClampInt(llround(_batteryPower * 100), INT16_MIN + 1, INT16_MAX);
	sample.adapterPower = isnan(_systemPowerIn) ? 0 : (uint16_t)VXClampInt(llround(_systemPowerIn * 10), 0, UINT16_MAX);
	sample.currentCapacity = (uint16_t)VXClampInt(_currentCapacity, 0, UINT16_MAX);
	sample.fullCapacity = (uint16_t)VXClampInt(_fullChargeCapacity, 0, UINT16_MAX);
	sample.cycles = (uint16_t)VXClampInt(_cycleCount, 0, UINT16_MAX);
	sample.health = isnan(_health) ? 0 : (uint16_t)VXClampInt(llround(_health * 100), 0, UINT16_MAX);
	return sample;
}

@end

#pragma mark - Estimates

NSInteger VXEstimateMinutes(VXBatteryInfo *info, double drainPerHour, NSInteger targetLevel) {
	if (info.plugged) {
		if (!info.charging || info.fullyCharged) return -1;
		NSInteger target = MIN(MAX(targetLevel, 1), 100);
		if (target <= info.level) return -1;
		double capacity = info.fullChargeCapacity > 0 ? info.fullChargeCapacity : (info.nominalCapacity > 0 ? info.nominalCapacity : info.designCapacity);
		double current = info.averageAmperage > 0 ? info.averageAmperage : info.amperage;
		if (capacity <= 0 || current < 30) return -1;
		// Constant current up to about 80 %, then the charger tapers off to roughly half the current.
		double fast = MAX(0, MIN(target, 80) - info.level);
		double slow = MAX(0, target - MAX(info.level, 80));
		double slowFactor = info.level < 80 ? 2 : 1;
		double minutes = (fast + slow * slowFactor) / 100.0 * capacity / current * 60;
		return minutes > 0 ? lround(minutes) : -1;
	}
	if (drainPerHour > 0.2) return lround(info.level / drainPerHour * 60);
	double draw = -(info.averageAmperage < 0 ? info.averageAmperage : info.amperage);
	if (draw > 20 && info.currentCapacity > 0) return lround(info.currentCapacity / draw * 60);
	return -1;
}

double VXDrainPerHour(NSArray<NSArray<NSNumber *> *> *entries, NSTimeInterval now) {
	for (NSNumber *window in @[@(3 * 3600), @(12 * 3600)]) {
		double drop = 0, seconds = 0;
		NSArray<NSNumber *> *previous = nil;
		for (NSArray<NSNumber *> *entry in entries) {
			if (entry.count < 3 || entry[0].doubleValue < now - window.doubleValue) {
				previous = nil;
				continue;
			}
			// Only consecutive entries without a charger and without a long gap count.
			if (previous && !previous[2].boolValue && !entry[2].boolValue) {
				double elapsed = entry[0].doubleValue - previous[0].doubleValue;
				if (elapsed > 0 && elapsed < 900) {
					drop += previous[1].doubleValue - entry[1].doubleValue;
					seconds += elapsed;
				}
			}
			previous = entry;
		}
		if (seconds >= 1800 && drop >= 2) return drop / (seconds / 3600);
	}
	return 0;
}

#pragma mark - VXBatteryControl

static void (^gWatchHandler)(void);

static void VXInterestChanged(void *refcon, vx_io_object_t service, uint32_t type, void *argument) {
	if (gWatchHandler) gWatchHandler();
}

@implementation VXBatteryControl

+ (BOOL)available {
	return VXBatteryService() && pIORegistryEntrySetCFProperties;
}

+ (int)setProperties:(NSDictionary *)properties {
	vx_io_object_t service = VXBatteryService();
	if (!service || !pIORegistryEntrySetCFProperties) return KERN_FAILURE;
	return pIORegistryEntrySetCFProperties(service, (__bridge CFTypeRef)properties);
}

// IsCharging stays YES, PredictiveChargingInhibit is the switch that actually stops the charger (iOS 13+).
+ (int)setChargingInhibited:(BOOL)inhibited {
	return [self setProperties:@{@"IsCharging": @YES, @"PredictiveChargingInhibit": @(inhibited)}];
}

+ (int)setInflowDisabled:(BOOL)disabled {
	return [self setProperties:@{@"ExternalConnected": @(!disabled)}];
}

+ (BOOL)watchOnQueue:(dispatch_queue_t)queue handler:(void (^)(void))handler {
	vx_io_object_t service = VXBatteryService();
	if (!service || !pIONotificationPortCreate || !pIONotificationPortSetDispatchQueue || !pIOServiceAddInterestNotification) return NO;
	static VXNotificationPortRef port;
	static vx_io_object_t notification;
	if (port) return YES;
	gWatchHandler = [handler copy];
	port = pIONotificationPortCreate(MACH_PORT_NULL);
	if (!port) return NO;
	pIONotificationPortSetDispatchQueue(port, queue);
	return pIOServiceAddInterestNotification(port, service, "IOGeneralInterest", VXInterestChanged, NULL, &notification) == KERN_SUCCESS;
}

@end
