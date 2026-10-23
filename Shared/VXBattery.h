#pragma once
#import <Foundation/Foundation.h>
#import "VXShared.h"

NS_ASSUME_NONNULL_BEGIN

// A snapshot of the AppleSmartBattery registry entry with the values MyLittleEnergy
// shows already converted (°C, V, W, mAh, minutes). Numbers that the device
// doesn't report are nil or -1, so the UI can hide them.
@interface VXBatteryInfo : NSObject

// Reads the battery now. nil when the registry entry can't be read.
+ (nullable instancetype)current;
- (instancetype)initWithProperties:(NSDictionary *)properties;

@property (nonatomic, readonly) NSDictionary *raw;
@property (nonatomic, readonly) NSDate *date;

@property (nonatomic, readonly) NSInteger level;              // %
@property (nonatomic, readonly) BOOL charging;
@property (nonatomic, readonly) BOOL externalConnected;
@property (nonatomic, readonly) BOOL externalChargeCapable;
@property (nonatomic, readonly) BOOL fullyCharged;
@property (nonatomic, readonly) BOOL adapterPresent;          // also true while MyLittleEnergy blocks the inflow
@property (nonatomic, readonly) BOOL plugged;                 // externalConnected || adapterPresent

@property (nonatomic, readonly) double temperature;           // °C, NAN if unknown
@property (nonatomic, readonly) double virtualTemperature;    // °C, NAN if unknown
@property (nonatomic, readonly) double voltage;               // V, NAN if unknown
@property (nonatomic, readonly) NSInteger amperage;           // mA, positive into the battery
@property (nonatomic, readonly) NSInteger averageAmperage;    // mA
@property (nonatomic, readonly) double batteryPower;          // W, positive into the battery
@property (nonatomic, readonly) double systemPowerIn;         // W from the charger, NAN if unknown
@property (nonatomic, readonly) double systemLoad;            // W the device uses, NAN if unknown

@property (nonatomic, readonly) NSInteger currentCapacity;    // mAh, -1 if unknown
@property (nonatomic, readonly) NSInteger fullChargeCapacity; // mAh
@property (nonatomic, readonly) NSInteger nominalCapacity;    // mAh
@property (nonatomic, readonly) NSInteger designCapacity;     // mAh
@property (nonatomic, readonly) double health;                // %, NAN if unknown
@property (nonatomic, readonly) BOOL healthFromSystem;        // health is iOS' own "Maximum Capacity"
@property (nonatomic, readonly) NSInteger cycleCount;
@property (nonatomic, readonly) NSInteger designCycleCount;
@property (nonatomic, readonly) NSInteger timeToEmpty;        // minutes, -1 if unknown
@property (nonatomic, readonly) NSInteger timeToFull;         // minutes, -1 if unknown

@property (nonatomic, readonly, nullable) NSString *serial;
@property (nonatomic, readonly, nullable) NSString *deviceName;
@property (nonatomic, readonly, nullable) NSString *firmware;
@property (nonatomic, readonly, nullable) NSString *chemistry;

@property (nonatomic, readonly, nullable) NSDictionary *adapter;
@property (nonatomic, readonly, nullable) NSString *adapterName;
@property (nonatomic, readonly, nullable) NSString *adapterManufacturer;
@property (nonatomic, readonly, nullable) NSString *adapterDescription;
@property (nonatomic, readonly) double adapterWatts;          // rated W, 0 if unknown
@property (nonatomic, readonly) double adapterVoltage;        // V, NAN if unknown
@property (nonatomic, readonly) NSInteger adapterCurrent;     // mA, -1 if unknown
@property (nonatomic, readonly) BOOL adapterWireless;

@property (nonatomic, readonly) NSArray<NSNumber *> *cellVoltages;   // mV
@property (nonatomic, readonly) NSArray<NSNumber *> *qmax;           // mAh
@property (nonatomic, readonly) NSInteger notChargingReason;         // -1 if unknown
@property (nonatomic, readonly) NSInteger chargingCurrent;           // mA the charger is asked for, -1
@property (nonatomic, readonly) NSInteger chargingVoltage;           // mV, -1
@property (nonatomic, readonly, nullable) NSDictionary *lifetime;
@property (nonatomic, readonly, nullable) NSDictionary *telemetry;
@property (nonatomic, readonly, nullable) NSNumber *chargeInhibited; // PredictiveChargingInhibit as reported

// Minutes to full while charging, to empty otherwise, -1 if unknown.
@property (nonatomic, readonly) NSInteger minutesRemaining;

- (VXLive)liveWithHeld:(BOOL)held;
- (VXSample)sampleWithFlags:(uint8_t)extraFlags;

@end

// Minutes until the battery reaches targetLevel while charging, or until it is empty otherwise; -1 if unknown.
// drainPerHour is the recent average drain in % per hour while unplugged (0 if there isn't enough
// history yet, then the current draw is used). The gas gauge's own AvgTimeToEmpty only looks at the
// last minute and is often a placeholder, so MyLittleEnergy doesn't use it for this.
FOUNDATION_EXPORT NSInteger VXEstimateMinutes(VXBatteryInfo *info, double drainPerHour, NSInteger targetLevel);

// Average drain in % per hour from [time, level, plugged] entries, oldest first: the last 3 hours
// unplugged if they hold enough data, else the last 12 hours. 0 when there isn't enough data.
FOUNDATION_EXPORT double VXDrainPerHour(NSArray<NSArray<NSNumber *> *> *entries, NSTimeInterval now);

// Writing to the battery needs root and the powersource-write entitlements, so only the daemon uses this.
@interface VXBatteryControl : NSObject
+ (BOOL)available;
// Stops charging, the charger keeps powering the device. Returns a kern_return_t.
+ (int)setChargingInhibited:(BOOL)inhibited;
// Disconnects the charger logically, the device runs on the battery.
+ (int)setInflowDisabled:(BOOL)disabled;
// Calls handler on queue whenever the battery driver publishes new values.
+ (BOOL)watchOnQueue:(dispatch_queue_t)queue handler:(void (^)(void))handler;
@end

NS_ASSUME_NONNULL_END
