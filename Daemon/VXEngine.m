#import "VXEngine.h"
#import "VXBattery.h"
#import "VXHistory.h"
#import "VXShared.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>

#ifndef VX_VERSION
#define VX_VERSION "0"
#endif

enum {
	VXControlNone = 0,
	VXControlInhibit = 1,
	VXControlBypass = 2,
};

// Alert and rule triggers, the app uses the same numbers.
enum {
	VXTriggerBelow = 0,
	VXTriggerAbove = 1,
	VXTriggerPlugged = 2,
	VXTriggerUnplugged = 3,
	VXTriggerHot = 4,
	VXTriggerFull = 5,
};

@implementation VXEngine {
	NSDictionary *_settings;
	VXBatteryInfo *_info;
	VXBatteryInfo *_previous;
	BOOL _limitHold;
	BOOL _heatHold;
	BOOL _fullOnce;
	int _applied;
	NSDate *_appliedAt;
	NSDate *_controlChangedAt;
	int _lastError;
	BOOL _screenOn;
	BOOL _testing;
	NSUInteger _testGeneration;
	NSString *_state;
	uint64_t _lastLive;

	dispatch_source_t _timer;
	NSTimeInterval _interval;
	BOOL _tickPending;
	NSDate *_lastTick;

	NSMutableArray<NSArray *> *_outbox;
	BOOL _pumping;
	NSInteger _sequence;

	uint32_t _lastStored;
	NSString *_lastPruneDay;
	NSString *_lastHealthDay;
	NSMutableDictionary *_session;

	NSString *_groupPath;
	NSDate *_groupLookup;
	NSMutableArray<NSArray<NSNumber *> *> *_levels;
	NSMutableArray<NSArray<NSNumber *> *> *_drainEntries;
	NSInteger _minutesLeft;

	NSDate *_started;
	NSDate *_lastStatusWrite;
	NSMutableArray<NSString *> *_log;
	NSDictionary *_selfTest;
}

+ (instancetype)shared {
	static VXEngine *shared;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ shared = [VXEngine new]; });
	return shared;
}

#pragma mark - Start

- (void)start {
	_started = [NSDate date];
	_log = [NSMutableArray array];
	_outbox = [NSMutableArray array];
	_screenOn = YES;
	_state = @"starting";
	VXEnsureDirectory();

	// Whatever a crashed previous run left behind is undone first.
	// Only what MyLittleEnergy itself changed is touched.
	NSDictionary *previous = VXReadPlist(VX_STATUS_PATH);
	if ([previous[@"applied"] intValue] == VXControlInhibit) [VXBatteryControl setChargingInhibited:NO];
	if ([previous[@"applied"] intValue] == VXControlBypass) [VXBatteryControl setInflowDisabled:NO];

	_lastStored = [VXHistory lastSampleTime];
	_levels = [[VXHistory levelsSince:NSDate.date.timeIntervalSince1970 - 86400 bucket:600] mutableCopy];
	_drainEntries = [[VXHistory drainEntriesSince:NSDate.date.timeIntervalSince1970 - 12 * 3600] mutableCopy];
	_minutesLeft = -1;
	[self reloadSettings];
	[self log:[NSString stringWithFormat:@"started, version %s, battery control %@", VX_VERSION, VXBatteryControl.available ? @"available" : @"missing"]];

	__weak VXEngine *weakSelf = self;
	[VXBatteryControl watchOnQueue:dispatch_get_main_queue() handler:^{ [weakSelf scheduleTick]; }];
	for (NSString *name in @[@"com.apple.system.powersources.source", @"com.apple.system.powersources.percent", @"com.apple.system.powersources.timeremaining"]) {
		VXObserve(name.UTF8String, ^(uint64_t state) { [weakSelf scheduleTick]; });
	}
	VXObserve("com.apple.springboard.hasBlankedScreen", ^(uint64_t state) {
		VXEngine *engine = weakSelf;
		if (!engine) return;
		engine->_screenOn = state == 0;
		[engine updateTimer];
		if (engine->_screenOn) [engine scheduleTick];
	});
	VXObserve(VX_NOTIFY_SETTINGS, ^(uint64_t state) {
		[weakSelf reloadSettings];
		[weakSelf scheduleTick];
	});
	VXObserve(VX_NOTIFY_LIVEMODE, ^(uint64_t state) {
		[weakSelf updateTimer];
		[weakSelf scheduleTick];
	});
	VXObserve(VX_NOTIFY_COMMAND, ^(uint64_t state) {
		NSInteger type = 0, value = 0;
		VXMessageUnpack(state, &type, &value);
		[weakSelf handleCommand:type value:value];
	});

	[self tick];
	[self updateTimer];
}

- (void)shutdown {
	[self cancelSelfTest];
	[self applyControl:VXControlNone];
	[self writeStatus:YES];
}

#pragma mark - Settings

- (void)reloadSettings {
	_settings = VXReadSettings();
	VXLook look = VXLookFromSettings(_settings);
	VXPostState(VX_NOTIFY_LOOK, VXLookPack(look));
	int32_t icon = VXParseHexColor(_settings[@"iconColor"]);
	int32_t charging = VXParseHexColor(_settings[@"iconChargingColor"]);
	uint64_t colors = (uint64_t)(icon < 0 ? 0x32D74B : icon) | ((uint64_t)(charging < 0 ? 0x0A84FF : charging) << 24);
	VXPostState(VX_NOTIFY_COLORS, colors);
	[self updateTimer];
}

- (BOOL)enabled {
	return VXSettingBool(_settings, @"enabled");
}

- (BOOL)scheduleActive {
	if (!VXSettingBool(_settings, @"scheduleEnabled")) return NO;
	NSDateComponents *now = [NSCalendar.currentCalendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:NSDate.date];
	NSInteger start = VXSettingInt(_settings, @"scheduleHour") * 60 + VXSettingInt(_settings, @"scheduleMinute");
	NSInteger minutes = now.hour * 60 + now.minute;
	NSInteger window = MAX(VXSettingInt(_settings, @"scheduleWindow"), 15);
	return (minutes - start + 1440) % 1440 < window;
}

#pragma mark - Timer

- (NSTimeInterval)wantedInterval {
	BOOL plugged = _info.plugged;
	BOOL live = VXGetState(VX_NOTIFY_LIVEMODE) > (uint64_t)NSDate.date.timeIntervalSince1970;
	VXLook look = VXLookFromSettings(_settings);
	BOOL statusBarLive = look.enabled && look.statusBarMode != VXStatusBarOff && (look.statusBarFields & (VXFieldPower | VXFieldTime | VXFieldAdapter))
		&& (plugged || !look.statusBarOnlyCharging);
	if (_screenOn && live) return 2;
	if (_screenOn && statusBarLive) return 5;
	if (plugged) return 20;
	return 60;
}

- (void)updateTimer {
	NSTimeInterval interval = [self wantedInterval];
	if (_timer && interval == _interval) return;
	if (_timer) dispatch_source_cancel(_timer);
	_interval = interval;
	_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), (uint64_t)(interval * NSEC_PER_SEC), (uint64_t)(interval * 0.2 * NSEC_PER_SEC));
	__weak VXEngine *weakSelf = self;
	dispatch_source_set_event_handler(_timer, ^{ [weakSelf tick]; });
	dispatch_resume(_timer);
}

// Battery notifications come in bursts, so they are coalesced.
- (void)scheduleTick {
	if (_tickPending) return;
	_tickPending = YES;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self->_tickPending = NO;
		[self tick];
	});
}

#pragma mark - Tick

- (void)tick {
	if (_testing) return;
	VXBatteryInfo *info = [VXBatteryInfo current];
	if (!info) {
		_state = @"no-battery";
		[self writeStatus:NO];
		return;
	}
	NSDate *now = info.date;
	NSTimeInterval elapsed = _lastTick ? [now timeIntervalSinceDate:_lastTick] : 0;
	_lastTick = now;
	BOOL enabled = [self enabled];
	BOOL plugged = info.plugged;
	BOOL wasPlugged = _previous ? _previous.plugged : plugged;

	if (wasPlugged && !plugged) {
		_fullOnce = NO;
		_limitHold = NO;
		_heatHold = NO;
	}

	int want = VXControlNone;
	NSString *state = plugged ? (info.charging ? @"charging" : (info.fullyCharged ? @"full" : @"not-charging")) : @"on-battery";
	if (enabled && plugged) {
		if (VXSettingBool(_settings, @"heatEnabled") && !isnan(info.temperature)) {
			double max = VXSettingDouble(_settings, @"heatMax");
			if (info.temperature >= max) {
				if (!_heatHold) {
					[self event:VXEventHeatPause value:lround(info.temperature * 10)];
					[self log:[NSString stringWithFormat:@"heat pause at %.1f °C", info.temperature]];
				}
				_heatHold = YES;
			} else if (info.temperature <= max - 2) {
				_heatHold = NO;
			}
		} else {
			_heatHold = NO;
		}

		BOOL override = _fullOnce || [self scheduleActive];
		if (VXSettingBool(_settings, @"limitEnabled") && !override) {
			NSInteger max = MIN(MAX(VXSettingInt(_settings, @"limitMax"), 20), 100);
			NSInteger resume = MIN(MAX(VXSettingInt(_settings, @"limitResume"), 5), max - 1);
			if (info.level >= max) {
				if (!_limitHold) {
					if (VXSettingBool(_settings, @"alertLimit")) [self event:VXEventLimitReached value:info.level];
					[self log:[NSString stringWithFormat:@"limit reached at %ld%%", (long)info.level]];
				}
				_limitHold = YES;
			} else if (info.level <= resume) {
				_limitHold = NO;
			}
		} else {
			_limitHold = NO;
		}

		if (_limitHold) {
			want = VXSettingInt(_settings, @"limitMode") == 1 ? VXControlBypass : VXControlInhibit;
			state = want == VXControlBypass ? @"bypass" : @"holding";
		}
		if (_heatHold) {
			if (want == VXControlNone) want = VXControlInhibit;
			state = @"heat";
		}
		if (override && VXSettingBool(_settings, @"limitEnabled") && !_heatHold) state = _fullOnce ? @"full-once" : @"schedule";
	}
	[self applyControl:want];
	_state = state;
	_info = info;

	[self recordDrain:info];
	_minutesLeft = [self estimateMinutes:info];
	if (_previous && enabled) [self detectEventsFrom:_previous to:info];
	[self trackSession:info elapsed:elapsed wasPlugged:wasPlugged];
	_previous = info;

	[self publishLive:info];
	[self storeSample:info];
	[self writeStatus:NO];
	[self updateTimer];
}

#pragma mark - Time left

// One entry a minute, or right away when the level or the charger changes.
- (void)recordDrain:(VXBatteryInfo *)info {
	NSTimeInterval now = info.date.timeIntervalSince1970;
	NSArray<NSNumber *> *last = _drainEntries.lastObject;
	BOOL changed = !last || last[1].integerValue != info.level || last[2].boolValue != info.plugged;
	if (changed || now - last[0].doubleValue >= 60) [_drainEntries addObject:@[@(now), @(info.level), @(info.plugged)]];
	while (_drainEntries.count && _drainEntries.firstObject[0].doubleValue < now - 12 * 3600) [_drainEntries removeObjectAtIndex:0];
}

// Where charging stops: the limit, unless it is lifted right now.
- (NSInteger)chargeTarget {
	if (VXSettingBool(_settings, @"limitEnabled") && !_fullOnce && ![self scheduleActive]) {
		return MIN(MAX(VXSettingInt(_settings, @"limitMax"), 20), 100);
	}
	return 100;
}

- (NSInteger)estimateMinutes:(VXBatteryInfo *)info {
	return VXEstimateMinutes(info, VXDrainPerHour(_drainEntries, info.date.timeIntervalSince1970), [self chargeTarget]);
}

#pragma mark - Charge control

- (void)applyControl:(int)want {
	BOOL reassert = want == _applied && want != VXControlNone && (!_appliedAt || -_appliedAt.timeIntervalSinceNow > 60);
	if (want == _applied && !reassert) return;
	int error = 0;
	if (_applied == VXControlInhibit && want != VXControlInhibit) error |= [VXBatteryControl setChargingInhibited:NO];
	if (_applied == VXControlBypass && want != VXControlBypass) error |= [VXBatteryControl setInflowDisabled:NO];
	if (want == VXControlInhibit) error |= [VXBatteryControl setChargingInhibited:YES];
	if (want == VXControlBypass) error |= [VXBatteryControl setInflowDisabled:YES];
	if (!reassert) _controlChangedAt = [NSDate date];
	if (!reassert || error) {
		NSArray *names = @[@"none", @"inhibit", @"bypass"];
		[self log:[NSString stringWithFormat:@"control %@ -> %@ (0x%x)", names[_applied], names[want], error]];
	}
	_applied = want;
	_appliedAt = [NSDate date];
	_lastError = error;
	[self writeStatus:YES];
}

#pragma mark - Events and rules

- (void)event:(NSInteger)type value:(NSInteger)value {
	[self send:VX_NOTIFY_EVENT type:type value:value];
}

- (void)send:(const char *)name type:(NSInteger)type value:(NSInteger)value {
	[_outbox addObject:@[@(name), @(type), @(value)]];
	[self pump];
}

// One notify state per name can only carry one message, so messages go out one at a time.
- (void)pump {
	if (_pumping || !_outbox.count) return;
	_pumping = YES;
	NSArray *message = _outbox.firstObject;
	[_outbox removeObjectAtIndex:0];
	VXPostState([message[0] UTF8String], VXMessagePack([message[1] integerValue], [message[2] integerValue], ++_sequence));
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		self->_pumping = NO;
		[self pump];
	});
}

static BOOL VXTriggered(NSInteger trigger, double value, VXBatteryInfo *before, VXBatteryInfo *after) {
	switch (trigger) {
		case VXTriggerBelow: return before.level > value && after.level <= value;
		case VXTriggerAbove: return before.level < value && after.level >= value;
		case VXTriggerPlugged: return !before.plugged && after.plugged;
		case VXTriggerUnplugged: return before.plugged && !after.plugged;
		case VXTriggerHot: return !isnan(after.temperature) && (isnan(before.temperature) || before.temperature < value) && after.temperature >= value;
		case VXTriggerFull: return after.plugged && ((!before.fullyCharged && after.fullyCharged) || (before.level < 100 && after.level >= 100));
	}
	return NO;
}

- (void)detectEventsFrom:(VXBatteryInfo *)before to:(VXBatteryInfo *)after {
	// Blocking the inflow can make the charger look unplugged for a moment; that isn't the user plugging anything.
	BOOL selfCaused = _controlChangedAt && -_controlChangedAt.timeIntervalSinceNow < 15;
	BOOL plugChange = before.plugged != after.plugged;
	if (selfCaused && plugChange) return;
	if (!before.plugged && after.plugged) [self event:VXEventPlugged value:lround(after.adapterWatts)];
	if (before.plugged && !after.plugged) [self event:VXEventUnplugged value:after.level];

	if (VXSettingBool(_settings, @"alertsEnabled")) {
		for (NSDictionary *alert in _settings[@"alertLevels"]) {
			if (![alert isKindOfClass:[NSDictionary class]] || ![alert[@"enabled"] boolValue]) continue;
			NSInteger level = [alert[@"level"] integerValue];
			BOOL up = [alert[@"up"] boolValue];
			if (up && after.plugged && VXTriggered(VXTriggerAbove, level, before, after)) [self event:VXEventLevelUp value:level];
			if (!up && !after.plugged && VXTriggered(VXTriggerBelow, level, before, after)) [self event:VXEventLevelDown value:level];
		}
		if (VXSettingBool(_settings, @"alertFull") && VXTriggered(VXTriggerFull, 0, before, after)) [self event:VXEventFull value:after.level];
		if (VXSettingBool(_settings, @"alertHot") && VXTriggered(VXTriggerHot, VXSettingDouble(_settings, @"alertHotTemp"), before, after)) {
			[self event:VXEventHot value:lround(after.temperature * 10)];
		}
	}

	NSArray *rules = _settings[@"rules"];
	if (![rules isKindOfClass:[NSArray class]]) return;
	[rules enumerateObjectsUsingBlock:^(NSDictionary *rule, NSUInteger index, BOOL *stop) {
		if (![rule isKindOfClass:[NSDictionary class]] || ![rule[@"enabled"] boolValue]) return;
		if (!VXTriggered([rule[@"trigger"] integerValue], [rule[@"value"] doubleValue], before, after)) return;
		[self log:[NSString stringWithFormat:@"rule %lu fired (%@)", (unsigned long)index, rule[@"title"] ?: rule[@"name"] ?: @""]];
		for (NSDictionary *action in rule[@"actions"]) {
			if (![action isKindOfClass:[NSDictionary class]]) continue;
			[self send:VX_NOTIFY_ACTION type:[action[@"type"] integerValue] value:[action[@"value"] integerValue]];
		}
		if ([rule[@"banner"] boolValue]) [self event:VXEventRuleFired value:index];
	}];
}

#pragma mark - Sessions

- (void)trackSession:(VXBatteryInfo *)info elapsed:(NSTimeInterval)elapsed wasPlugged:(BOOL)wasPlugged {
	if (info.plugged && !_session) {
		_session = [@{
			@"start": @(info.date.timeIntervalSince1970),
			@"startLevel": @(info.level),
			@"endLevel": @(info.level),
			@"maxTemp": @(isnan(info.temperature) ? 0 : info.temperature),
			@"energy": @0,
			@"peakPower": @0,
			@"heldSeconds": @0,
			@"wireless": @(info.adapterWireless),
		} mutableCopy];
	}
	if (_session && info.plugged) {
		if (elapsed > 0 && elapsed < 600) {
			if (info.batteryPower > 0) _session[@"energy"] = @([_session[@"energy"] doubleValue] + info.batteryPower * elapsed / 3600.0);
			if (_applied != VXControlNone) _session[@"heldSeconds"] = @([_session[@"heldSeconds"] doubleValue] + elapsed);
		}
		_session[@"endLevel"] = @(info.level);
		_session[@"end"] = @(info.date.timeIntervalSince1970);
		if (!isnan(info.temperature)) _session[@"maxTemp"] = @(MAX([_session[@"maxTemp"] doubleValue], info.temperature));
		_session[@"peakPower"] = @(MAX([_session[@"peakPower"] doubleValue], info.batteryPower));
		if (info.adapterWatts > 0) _session[@"adapterWatts"] = @(info.adapterWatts);
		NSString *charger = info.adapterName ?: info.adapterDescription;
		if (charger && ![charger isEqualToString:@"batt"]) _session[@"charger"] = charger;
		if (info.adapterManufacturer) _session[@"manufacturer"] = info.adapterManufacturer;
	}
	if (_session && !info.plugged) {
		_session[@"end"] = @(info.date.timeIntervalSince1970);
		NSTimeInterval duration = [_session[@"end"] doubleValue] - [_session[@"start"] doubleValue];
		if (duration >= 60) {
			[VXHistory appendSession:_session];
			VXPost(VX_NOTIFY_STATUS);
		}
		_session = nil;
	}
}

#pragma mark - Publishing

- (void)publishLive:(VXBatteryInfo *)info {
	VXLive state = [info liveWithHeld:_applied != VXControlNone];
	state.minutes = _minutesLeft;
	uint64_t live = [self enabled] ? VXLivePack(state) : 0;
	if (live == _lastLive) return;
	_lastLive = live;
	VXPostState(VX_NOTIFY_LIVE, live);
}

- (void)storeSample:(VXBatteryInfo *)info {
	uint32_t now = (uint32_t)info.date.timeIntervalSince1970;
	NSInteger interval = MAX(VXSettingInt(_settings, @"sampleInterval"), 30);
	BOOL plugChange = _previous && _previous.plugged != info.plugged;
	if (_lastStored && now - _lastStored < interval - 2 && !plugChange) return;
	_lastStored = now;

	uint8_t flags = 0;
	if (_applied != VXControlNone) flags |= VXSampleHeld;
	if (_applied == VXControlBypass) flags |= VXSampleBypass;
	if (NSProcessInfo.processInfo.lowPowerModeEnabled) flags |= VXSampleLowPower;
	if (_screenOn) flags |= VXSampleScreenOn;
	[VXHistory appendSample:[info sampleWithFlags:flags]];

	NSArray *last = _levels.lastObject;
	if (!last || now - [last[0] unsignedIntValue] >= 600 || plugChange) [_levels addObject:@[@(now), @(info.level)]];
	while (_levels.count && [_levels.firstObject[0] unsignedIntValue] < now - 86400) [_levels removeObjectAtIndex:0];

	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.dateFormat = @"yyyy-MM-dd";
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	NSString *day = [formatter stringFromDate:info.date];
	if (![day isEqualToString:_lastHealthDay] && !isnan(info.health)) {
		_lastHealthDay = day;
		[VXHistory recordHealth:@{
			@"health": @(round(info.health * 10) / 10),
			@"full": @(info.fullChargeCapacity),
			@"nominal": @(info.nominalCapacity),
			@"design": @(info.designCapacity),
			@"cycles": @(info.cycleCount),
		} forDay:day];
	}
	if (![day isEqualToString:_lastPruneDay]) {
		_lastPruneDay = day;
		[VXHistory pruneOlderThanDays:VXSettingInt(_settings, @"retentionDays")];
	}
	[self writeWidgetSnapshot:info];
	VXPost(VX_NOTIFY_STATUS);
}

- (NSString *)groupPath {
	if (_groupPath) return _groupPath;
	if (_groupLookup && -_groupLookup.timeIntervalSinceNow < 600) return nil;
	_groupLookup = [NSDate date];
	dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
	Class proxyClass = NSClassFromString(@"LSApplicationProxy");
	SEL lookup = NSSelectorFromString(@"applicationProxyForIdentifier:");
	if ([proxyClass respondsToSelector:lookup]) {
		id proxy = ((id (*)(id, SEL, NSString *))objc_msgSend)(proxyClass, lookup, VX_BUNDLE_ID);
		SEL groups = NSSelectorFromString(@"groupContainerURLs");
		if ([proxy respondsToSelector:groups]) {
			NSDictionary *urls = ((id (*)(id, SEL))objc_msgSend)(proxy, groups);
			NSURL *url = [urls isKindOfClass:[NSDictionary class]] ? urls[VX_GROUP_ID] : nil;
			if ([url isKindOfClass:[NSURL class]]) _groupPath = url.path;
		}
	}
	if (!_groupPath) {
		NSString *stored = _settings[@"groupPath"];
		if ([stored isKindOfClass:[NSString class]] && [NSFileManager.defaultManager fileExistsAtPath:stored]) _groupPath = stored;
	}
	return _groupPath;
}

- (void)writeWidgetSnapshot:(VXBatteryInfo *)info {
	NSMutableDictionary *snapshot = [@{
		@"time": @(info.date.timeIntervalSince1970),
		@"level": @(info.level),
		@"charging": @(info.charging),
		@"plugged": @(info.plugged),
		@"full": @(info.fullyCharged),
		@"held": @(_applied != VXControlNone),
		@"power": @(round(info.batteryPower * 10) / 10),
		@"minutes": @(_minutesLeft),
		@"cycles": @(info.cycleCount),
		@"adapterWatts": @(info.adapterWatts),
		@"limitEnabled": @(VXSettingBool(_settings, @"limitEnabled")),
		@"limitMax": @(VXSettingInt(_settings, @"limitMax")),
		@"state": _state ?: @"",
		@"fahrenheit": @(VXSettingInt(_settings, @"tempUnit") == 1),
		@"accent": _settings[@"accentColor"] ?: @"#32D74B",
		@"levels": _levels ?: @[],
	} mutableCopy];
	if (!isnan(info.temperature)) snapshot[@"temperature"] = @(round(info.temperature * 10) / 10);
	if (!isnan(info.health)) snapshot[@"health"] = @(round(info.health * 10) / 10);
	VXWriteJSON([VX_DIR stringByAppendingPathComponent:VX_WIDGET_FILE], snapshot);
	NSString *group = [self groupPath];
	if (group) VXWriteJSON([group stringByAppendingPathComponent:VX_WIDGET_FILE], snapshot);
}

- (void)writeStatus:(BOOL)force {
	if (!force && _lastStatusWrite && -_lastStatusWrite.timeIntervalSinceNow < 10) return;
	_lastStatusWrite = [NSDate date];
	NSMutableDictionary *status = [@{
		@"version": @VX_VERSION,
		@"pid": @(getpid()),
		@"started": @(_started.timeIntervalSince1970),
		@"updated": @(NSDate.date.timeIntervalSince1970),
		@"state": _state ?: @"",
		@"applied": @(_applied),
		@"plugged": @(_info.plugged),
		@"fullOnce": @(_fullOnce),
		@"limitHold": @(_limitHold),
		@"heatHold": @(_heatHold),
		@"scheduleActive": @([self scheduleActive]),
		@"lastError": @(_lastError),
		@"controlAvailable": @(VXBatteryControl.available),
		@"interval": @(_interval),
		@"screenOn": @(_screenOn),
		@"minutesLeft": @(_minutesLeft),
		@"chargeTarget": @([self chargeTarget]),
		@"drainPerHour": @(VXDrainPerHour(_drainEntries, NSDate.date.timeIntervalSince1970)),
		@"log": [_log copy] ?: @[],
	} mutableCopy];
	if (_session) status[@"session"] = [_session copy];
	if (_selfTest) status[@"selfTest"] = _selfTest;
	if (_groupPath) status[@"groupPath"] = _groupPath;
	if (VXWritePlist(VX_STATUS_PATH, status)) VXPost(VX_NOTIFY_STATUS);
}

- (void)log:(NSString *)message {
	NSLog(@"[mylittleenergyd] %@", message);
	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.dateFormat = @"MM-dd HH:mm:ss";
	[_log addObject:[NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:NSDate.date], message]];
	if (_log.count > 60) [_log removeObjectsInRange:NSMakeRange(0, _log.count - 60)];
}

#pragma mark - Commands

- (void)handleCommand:(NSInteger)type value:(NSInteger)value {
	switch (type) {
		case VXCommandReload:
			[self reloadSettings];
			[self tick];
			break;
		case VXCommandFullOnce:
			_fullOnce = YES;
			_limitHold = NO;
			[self log:@"charging to 100% once"];
			[self tick];
			[self writeStatus:YES];
			break;
		case VXCommandCancelFullOnce:
			_fullOnce = NO;
			[self tick];
			[self writeStatus:YES];
			break;
		case VXCommandSelfTest:
			[self runSelfTest];
			break;
		case VXCommandClearHistory:
			[VXHistory clearAll];
			[_levels removeAllObjects];
			[_drainEntries removeAllObjects];
			_lastStored = 0;
			_lastHealthDay = nil;
			[self log:@"history cleared"];
			[self tick];
			VXPost(VX_NOTIFY_STATUS);
			break;
		case VXCommandWriteStatus:
			[self writeStatus:YES];
			VXPost(VX_NOTIFY_STATUS);
			break;
		case VXCommandTestAlert:
			[self event:VXEventTest value:_info.level];
			break;
	}
}

// Briefly flips each control and checks that the battery driver reacts.
// Charging pauses for a few seconds, so the app only offers this while plugged in.
- (void)cancelSelfTest {
	if (!_testing) return;
	_testGeneration++;
	_testing = NO;
	// These keys were changed by this test; restore them even if battery reads fail.
	[VXBatteryControl setChargingInhibited:NO];
	[VXBatteryControl setInflowDisabled:NO];
}

- (void)runSelfTest {
	if (_testing) return;
	VXBatteryInfo *before = [VXBatteryInfo current];
	NSMutableDictionary *results = [@{
		@"time": @(NSDate.date.timeIntervalSince1970),
		@"readable": @(before != nil),
		@"keys": @(before.raw.count),
		@"controlAvailable": @(VXBatteryControl.available),
		@"plugged": @(before.plugged),
	} mutableCopy];
	if (!before.plugged) {
		_selfTest = results;
		[self writeStatus:YES];
		VXPost(VX_NOTIFY_STATUS);
		return;
	}
	_testing = YES;
	NSUInteger generation = ++_testGeneration;
	[self log:@"self test started"];
	if (_applied == VXControlInhibit) [VXBatteryControl setChargingInhibited:NO];
	if (_applied == VXControlBypass) [VXBatteryControl setInflowDisabled:NO];
	_applied = VXControlNone;

	results[@"inhibitResult"] = @([VXBatteryControl setChargingInhibited:YES]);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
		if (!self->_testing || self->_testGeneration != generation) return;
		VXBatteryInfo *inhibited = [VXBatteryInfo current];
		results[@"inhibitAmperage"] = @(inhibited.amperage);
		results[@"inhibitCharging"] = @(inhibited.charging);
		results[@"inhibitReported"] = inhibited.chargeInhibited ?: @(-1);
		results[@"inhibitWorks"] = @(!inhibited.charging || inhibited.amperage < MAX(before.amperage / 3, 60));
		[VXBatteryControl setChargingInhibited:NO];
		results[@"bypassResult"] = @([VXBatteryControl setInflowDisabled:YES]);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			if (!self->_testing || self->_testGeneration != generation) return;
			VXBatteryInfo *bypass = [VXBatteryInfo current];
			results[@"bypassAmperage"] = @(bypass.amperage);
			results[@"bypassExternal"] = @(bypass.externalConnected);
			results[@"bypassWorks"] = @(bypass.amperage < 0 || !bypass.externalConnected);
			[VXBatteryControl setInflowDisabled:NO];
			self->_selfTest = results;
			self->_testing = NO;
			self->_appliedAt = nil;
			[self log:[NSString stringWithFormat:@"self test done: inhibit %@, bypass %@", results[@"inhibitWorks"], results[@"bypassWorks"]]];
			// The next tick puts the limit back if it was holding.
			[self tick];
			[self writeStatus:YES];
			VXPost(VX_NOTIFY_STATUS);
		});
	});
}

@end
