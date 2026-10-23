#import <Foundation/Foundation.h>
#import "VXShared.h"

// history.bin (samples), sessions.json (charging sessions) and health.json (one entry per day).
@interface VXHistory : NSObject
+ (void)appendSample:(VXSample)sample;
+ (uint32_t)lastSampleTime;
+ (void)pruneOlderThanDays:(NSInteger)days;
// [time, level] pairs, at most one per bucket seconds, for the widget chart.
+ (NSArray<NSArray<NSNumber *> *> *)levelsSince:(NSTimeInterval)since bucket:(NSTimeInterval)bucket;
// [time, level, plugged] for every sample since then, oldest first.
+ (NSArray<NSArray<NSNumber *> *> *)drainEntriesSince:(NSTimeInterval)since;

+ (void)appendSession:(NSDictionary *)session;
+ (void)recordHealth:(NSDictionary *)entry forDay:(NSString *)day;

+ (void)clearAll;
@end
