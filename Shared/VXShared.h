#pragma once
#import <Foundation/Foundation.h>

// Everything the daemon, the SpringBoard tweak, the app, the widgets and the
// Control Center module agree on: paths, Darwin notification names and the
// packed notify states sandboxed apps read (they can't open our files).

#define VX_BUNDLE_ID @"com.xsxs18.mylittleenergy"
#define VX_GROUP_ID @"group.com.xsxs18.mylittleenergy"
NSString *VXJailbreakPath(NSString *path);
NSString *VXDataDirectory(void);
#define VX_APP_PATH VXJailbreakPath(@"/Applications/MyLittleEnergy.app")

#define VX_DIR VXDataDirectory()
#define VX_SETTINGS_PATH [VX_DIR stringByAppendingPathComponent:@"settings.plist"]
#define VX_STATUS_PATH [VX_DIR stringByAppendingPathComponent:@"status.plist"]
#define VX_HISTORY_PATH [VX_DIR stringByAppendingPathComponent:@"history.bin"]
#define VX_SESSIONS_PATH [VX_DIR stringByAppendingPathComponent:@"sessions.json"]
#define VX_HEALTH_PATH [VX_DIR stringByAppendingPathComponent:@"health.json"]
#define VX_WIDGET_FILE @"widget.json"
#define VX_HUD_PATH [VX_DIR stringByAppendingPathComponent:@"hud.plist"]
#define VX_SB_STATUS_PATH [VX_DIR stringByAppendingPathComponent:@"springboard.plist"]

// app/CC module -> everyone: settings.plist was rewritten
#define VX_NOTIFY_SETTINGS "com.xsxs18.mylittleenergy.settings"
// daemon -> everyone, state = VXLive packed
#define VX_NOTIFY_LIVE "com.xsxs18.mylittleenergy.live"
// daemon -> everyone, state = VXLook packed
#define VX_NOTIFY_LOOK "com.xsxs18.mylittleenergy.look"
// daemon -> everyone, state = icon color (bits 0-23) and charging color (bits 24-47)
#define VX_NOTIFY_COLORS "com.xsxs18.mylittleenergy.colors"
// daemon -> SpringBoard, state = VXEvent packed
#define VX_NOTIFY_EVENT "com.xsxs18.mylittleenergy.event"
// daemon -> SpringBoard, state = VXAction packed
#define VX_NOTIFY_ACTION "com.xsxs18.mylittleenergy.action"
// app/CC module -> daemon, state = VXCommand
#define VX_NOTIFY_COMMAND "com.xsxs18.mylittleenergy.command"
// daemon -> app: status.plist, history or sessions changed
#define VX_NOTIFY_STATUS "com.xsxs18.mylittleenergy.status"
// app/SpringBoard -> daemon, state = unix time until which fast updates are wanted
#define VX_NOTIFY_LIVEMODE "com.xsxs18.mylittleenergy.livemode"
// SpringBoard -> app: springboard.plist (tweak status) was written
#define VX_NOTIFY_SB_STATUS "com.xsxs18.mylittleenergy.sbstatus"
// app -> SpringBoard, state = VXSBTest*
#define VX_NOTIFY_SB_TEST "com.xsxs18.mylittleenergy.sbtest"

enum {
	VXSBTestStatus = 1,       // write springboard.plist
	VXSBTestAnimation = 2,    // show the charging animation now
	VXSBTestBanner = 3,       // banner, sound and speech
	VXSBTestSound = 4,        // value = index into the sound list is not needed, plays alertSound
};

#pragma mark - Live battery state

typedef struct {
	BOOL valid;
	NSInteger level;          // %
	BOOL charging;
	BOOL external;
	BOOL full;
	BOOL held;                // MyLittleEnergy is holding the charge (limit, heat, bypass)
	double power;             // W into the battery, negative while discharging
	double temperature;       // °C
	NSInteger minutes;        // to full while charging, to empty otherwise, -1 unknown
	NSInteger health;         // %
	NSInteger adapterWatts;
} VXLive;

FOUNDATION_EXPORT uint64_t VXLivePack(VXLive live);
FOUNDATION_EXPORT VXLive VXLiveUnpack(uint64_t state);

#pragma mark - Status bar and battery icon look

enum {
	VXStatusBarOff = 0,
	VXStatusBarTwoLines = 1,
	VXStatusBarReplace = 2,
	VXStatusBarAppend = 3,
};

enum {
	VXFieldPower = 1 << 0,
	VXFieldTemperature = 1 << 1,
	VXFieldPercent = 1 << 2,
	VXFieldTime = 1 << 3,
	VXFieldAdapter = 1 << 4,
	VXFieldHealth = 1 << 5,
};

enum {
	VXIconSystem = 0,
	VXIconCustom = 1,
	VXIconByLevel = 2,
};

typedef struct {
	NSInteger statusBarMode;
	NSInteger statusBarFields;
	BOOL statusBarOnlyCharging;
	NSInteger iconMode;
	BOOL iconChargingCustom;
	NSInteger iconLowThreshold;   // % at which the icon turns red
	BOOL fahrenheit;
	BOOL enabled;
} VXLook;

FOUNDATION_EXPORT uint64_t VXLookPack(VXLook look);
FOUNDATION_EXPORT VXLook VXLookUnpack(uint64_t state);
// What the status bar shows for these values, nil when it shows nothing.
FOUNDATION_EXPORT NSString *VXStatusBarText(VXLook look, VXLive live, NSString *separator);

#pragma mark - Events (daemon -> SpringBoard)

enum {
	VXEventNone = 0,
	VXEventLevelDown = 1,     // value = threshold
	VXEventLevelUp = 2,       // value = threshold
	VXEventFull = 3,
	VXEventHot = 4,           // value = °C * 10
	VXEventPlugged = 5,       // value = adapter watts
	VXEventUnplugged = 6,     // value = level
	VXEventLimitReached = 7,  // value = level
	VXEventHeatPause = 8,     // value = °C * 10
	VXEventRuleFired = 9,     // value = rule index
	VXEventTest = 10,
};

enum {
	VXActionNone = 0,
	VXActionLowPower = 1,     // value 0/1
	VXActionWiFi = 2,
	VXActionBluetooth = 3,
	VXActionBrightness = 4,   // value 0-100
	VXActionDarkMode = 5,     // value 0/1
	VXActionAirplane = 6,
	VXActionLocation = 7,
};

enum {
	VXCommandNone = 0,
	VXCommandReload = 1,
	VXCommandFullOnce = 2,
	VXCommandCancelFullOnce = 3,
	VXCommandSelfTest = 4,
	VXCommandClearHistory = 5,
	VXCommandWriteStatus = 6,
	VXCommandTestAlert = 7,
};

FOUNDATION_EXPORT uint64_t VXMessagePack(NSInteger type, NSInteger value, NSInteger sequence);
FOUNDATION_EXPORT void VXMessageUnpack(uint64_t state, NSInteger *type, NSInteger *value);

#pragma mark - Notify helpers

FOUNDATION_EXPORT void VXPost(const char *name);
FOUNDATION_EXPORT void VXPostState(const char *name, uint64_t state);
FOUNDATION_EXPORT uint64_t VXGetState(const char *name);
// Runs on the main queue. Returns the token.
FOUNDATION_EXPORT int VXObserve(const char *name, void (^handler)(uint64_t state));

#pragma mark - Settings

// Every setting with its default. The app shows these, the daemon and the tweak fall back to them.
FOUNDATION_EXPORT NSDictionary *VXSettingsDefaults(void);
// settings.plist merged over the defaults.
FOUNDATION_EXPORT NSDictionary *VXReadSettings(void);
// Writes settings.plist (only the values that differ from the defaults are kept) and posts VX_NOTIFY_SETTINGS.
FOUNDATION_EXPORT BOOL VXWriteSettings(NSDictionary *settings);
FOUNDATION_EXPORT BOOL VXSettingBool(NSDictionary *settings, NSString *key);
FOUNDATION_EXPORT NSInteger VXSettingInt(NSDictionary *settings, NSString *key);
FOUNDATION_EXPORT double VXSettingDouble(NSDictionary *settings, NSString *key);
FOUNDATION_EXPORT VXLook VXLookFromSettings(NSDictionary *settings);
// "#RRGGBB" -> 0xRRGGBB, -1 when invalid.
FOUNDATION_EXPORT int32_t VXParseHexColor(NSString *hex);

#pragma mark - Files

FOUNDATION_EXPORT void VXEnsureDirectory(void);
// Atomic write; files written by root are handed to mobile so the app can read and replace them.
FOUNDATION_EXPORT BOOL VXWriteFile(NSString *path, NSData *data);
FOUNDATION_EXPORT id VXReadJSON(NSString *path);
FOUNDATION_EXPORT BOOL VXWriteJSON(NSString *path, id object);
FOUNDATION_EXPORT NSDictionary *VXReadPlist(NSString *path);
FOUNDATION_EXPORT BOOL VXWritePlist(NSString *path, NSDictionary *plist);

#pragma mark - History file

// One record per sample, appended to history.bin. Little endian, 24 bytes.
typedef struct __attribute__((packed)) {
	uint32_t time;            // unix seconds
	uint8_t level;            // %
	uint8_t flags;            // VXSampleFlag*
	int16_t temperature;      // 0.01 °C
	uint16_t voltage;         // mV
	int16_t amperage;         // mA, positive into the battery
	int16_t power;            // 0.01 W, positive into the battery
	uint16_t adapterPower;    // 0.1 W drawn from the charger
	uint16_t currentCapacity; // mAh
	uint16_t fullCapacity;    // mAh
	uint16_t cycles;
	uint16_t health;          // 0.01 %
} VXSample;

enum {
	VXSampleCharging = 1 << 0,
	VXSampleExternal = 1 << 1,
	VXSampleFull = 1 << 2,
	VXSampleHeld = 1 << 3,
	VXSampleBypass = 1 << 4,
	VXSampleLowPower = 1 << 5,
	VXSampleScreenOn = 1 << 6,
};

#pragma mark - Strings

// Localized string from the app bundle (the tweak and the CC module have no strings of their own).
FOUNDATION_EXPORT NSString *VXL(NSString *key);
